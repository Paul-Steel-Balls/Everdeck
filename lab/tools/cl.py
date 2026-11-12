# cl.py NAME PATCH START_DIR START_POOL ROUNDS [CLASSES] -> planner converge-lite: search (2 seeds x ITERS) vs prev field, pool, pick
import json,sys,subprocess,os,glob
from concurrent.futures import ThreadPoolExecutor
P=os.path.dirname(os.path.abspath(__file__)); L='/home/claude/everdeck/lab/target/release/everdeck_lab'
name,patch,start,pool0,R=sys.argv[1:6]; R=int(R); R0=int(os.environ.get("R0","1"))
CL=(sys.argv[6] if len(sys.argv)>6 else 'grunk,agatha,presto,barnacle,reginald,larry').split(',')
IT=os.environ.get('ITERS','200'); VAR=['--variant',os.environ['VARIANT']] if os.environ.get('VARIANT') else []
out=f'{P}/cl/{name}'; os.makedirs(out,exist_ok=True)
prev=start; pool=json.load(open(pool0))
for r in range(R0,R0+R):
    jobs=[(c,s) for c in CL for s in (401+r*10,402+r*10)]
    def run(j):
        c,s=j; f=f'{out}/r{r}_{c}_{s}.json'
        subprocess.run([L,'search']+VAR+['--patch',patch,'--class',c,'--iters',IT,'--games','300','--seed',str(s),'--field',prev+'/field.json','--start',prev+'/best.json','--out',f,'--plan','4'],capture_output=True)
        return c,json.load(open(f))['deck']
    with ThreadPoolExecutor(2) as ex:
        for c,d in ex.map(run,jobs): pool[c].append(d)
    json.dump(pool,open(f'{out}/pool_r{r}.json','w'))
    d=f'{out}/r{r}'
    subprocess.run([L,'pick']+VAR+['--patch',patch,'--pool',f'{out}/pool_r{r}.json','--games',os.environ.get('PG','300'),'--seed',str(r),'--plan','4','--out',d],capture_output=True)
    t=open(d+'/report.txt').read().splitlines()
    print(f'== {name} round {r}:', ' | '.join(' '.join(l.split()[:2]) for l in t[1:7]), '|', t[7].split()[2],flush=True)
    k=[i for i,l in enumerate(t) if l.startswith('row beats')][0]; names=t[k+1].split(); bad=[]
    for row in t[k+2:k+8]:
        p=row.split()
        for j,v in enumerate(p[1:]):
            if v!='-' and float(v[:-1])<40: bad.append(f'{p[0]} v {names[j]} {v}')
    print('   outside 60/40:', ', '.join(bad) or 'none',flush=True)
    prev=d
