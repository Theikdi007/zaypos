#!/usr/bin/env python3
"""QA r16 server checks for BUG-52 (curl-equivalent, urllib).
  srv.py pull                 -> login as a curl device, pull, print customers/products names + code points
  srv.py push                 -> push an upsertCustomer + upsertProduct with ZAWGYI text (an old app), then pull them
Prints the exact requests (no token) and responses."""
import json, sys, uuid, datetime, urllib.request

BASE = 'http://127.0.0.1:5076/api/v1'
PHONE, PIN = '+95979091716', '111111'
DEV = '0193aaaa-0000-7000-8000-00000000r16c'.replace('r16c', '0016')


def cps(s):
    return ' '.join('U+%04X' % ord(c) for c in s)


def call(method, path, body=None, token=None):
    data = json.dumps(body, ensure_ascii=False).encode() if body is not None else None
    req = urllib.request.Request(BASE + path, data=data, method=method)
    req.add_header('Content-Type', 'application/json')
    if token:
        req.add_header('Authorization', 'Bearer ' + token)
    try:
        with urllib.request.urlopen(req) as r:
            return r.status, json.loads(r.read() or b'null')
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()


def login():
    st, r = call('POST', '/auth/login', {'phone': PHONE, 'pin': PIN, 'device': {'id': DEV, 'name': 'QA r16 curl'}})
    print('POST /auth/login ->', st)
    if st != 200:
        print(r); sys.exit(1)
    return r


def pull(tok):
    cur, out = '', {}
    while True:
        st, r = call('GET', '/sync/pull?cursor=%s&limit=500' % cur, token=tok)
        assert st == 200, (st, r)
        for t, rows in r['changes'].items():
            out.setdefault(t, []).extend(rows)
        cur = r.get('cursor') or r.get('nextCursor') or ''
        if not r.get('hasMore'):
            break
    return out


def show(changes):
    for t in ('customers', 'products'):
        for row in changes.get(t, []):
            for k in ('name', 'address', 'note'):
                v = row.get(k)
                if v and any('က' <= ch <= '႟' for ch in v):
                    print('%s %s %s=%r [%s]' % (t, row['id'][:8], k, v, cps(v)))


tok = login()
access = tok.get('accessToken') or tok.get('access_token')
tenant = tok.get('tenantId') or (tok.get('session') or {}).get('tenantId')
if sys.argv[1] == 'pull':
    print('GET /sync/pull (all pages)')
    show(pull(access))
elif sys.argv[1] == 'push':
    ch = pull(access)
    tenant = tenant or ch['tenants'][0]['id']
    tmpl_c = next(iter(ch['customers']))
    tmpl_p = next(iter(ch['products']))
    now = datetime.datetime.now(datetime.timezone.utc).isoformat(timespec='milliseconds').replace('+00:00', 'Z')
    cust = dict(tmpl_c, id=str(uuid.uuid4()), name='ေက်ာ္ေက်ာ္', phone='09790917199', address='ရန္ကုန္',
                note='ေၾကြးက်န္', createdAt=now, updatedAt=now)
    cust2 = dict(tmpl_c, id=str(uuid.uuid4()), name='ယခု မိုးရွာနေပါသလား', phone='09790917198', address='ကျွန်ုပ်',
                 note=None, createdAt=now, updatedAt=now)
    prod = dict(tmpl_p, id=str(uuid.uuid4()), name='ၾကက္ဥ', createdAt=now, updatedAt=now)
    for r in (cust, cust2, prod):
        r.pop('rowVersion', None); r.pop('version', None)
    units = [
        {'unitId': str(uuid.uuid4()), 'kind': 'upsertCustomer', 'clientTime': now, 'rows': {'customers': [cust, cust2]}},
        {'unitId': str(uuid.uuid4()), 'kind': 'upsertProduct', 'clientTime': now, 'rows': {'products': [prod]}},
    ]
    for u in units:
        for rows in u['rows'].values():
            for r in rows:
                for k in ('name', 'address', 'note'):
                    if r.get(k):
                        print('PUSH %s %s=%r [%s]' % (u['kind'], k, r[k], cps(r[k])))
    import subprocess
    open('push_body.json', 'w').write(json.dumps({'deviceId': DEV, 'units': units}, ensure_ascii=False))
    print('$ curl -s -w "\\nHTTP %{http_code}" -X POST http://127.0.0.1:5076/api/v1/sync/push -H "Authorization: Bearer <token>" '
          '-H "Content-Type: application/json" --data-binary @push_body.json')
    out = subprocess.run(['curl', '-s', '-w', '\nHTTP %{http_code}', '-X', 'POST', BASE + '/sync/push',
                          '-H', 'Authorization: Bearer ' + access, '-H', 'Content-Type: application/json',
                          '--data-binary', '@push_body.json'], capture_output=True, text=True).stdout
    print(out)
    print('GET /sync/pull (all pages) — the pushed rows:')
    ids = {cust['id'], cust2['id'], prod['id']}
    after = pull(access)
    show({t: [x for x in after.get(t, []) if x['id'] in ids] for t in ('customers', 'products')})
