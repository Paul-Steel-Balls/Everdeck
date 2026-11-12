# usage: knock.py DECKS PATCH OUTDIR CLASS[,CLASS] -> each card swapped for a vanilla of the same cost; Boss win% delta
import json,sys,subprocess,os,re
decks_f,patch,out,classes=sys.argv[1:5]
L=os.environ.get('LAB','/home/claude/everdeck/lab/target/release/everdeck_lab')
G=os.environ.get('G','400')
decks=json.load(open(decks_f))
cost={}
for line in subprocess.run([L,'cards','--patch',patch],capture_output=True,text=True).stdout.splitlines():
    m=re.match(r'(\S+)\s+.*?\((\d+)\)',line)
    if m: cost[m.group(1)]=int(m.group(2))
van={0:'angry_squirrel',1:'angry_squirrel',2:'guard_dog',3:'knight',4:'ogre',5:'giant',6:'dragon'}
def wr(d,tag):
    f=f'{out}/{tag}.json'; json.dump(d,open(f,'w'))
    r=subprocess.run([L,'meta','--patch',patch,'--decks',f,'--games',G,'--seed','5','--plan','4','--threads','2'],capture_output=True,text=True).stdout
    res={}
    for l in r.splitlines():
        if l.startswith('going'): break
        p=l.split()
        if len(p)>=2 and p[0] in decks and p[1].endswith('%'): res[p[0]]=float(p[1][:-1])
    return res
os.makedirs(out,exist_ok=True)
base=wr(decks,'base'); print('base',base,flush=True)
for C in classes.split(','):
    rows=[]
    for c in sorted(set(decks[C])):
        v=van[min(cost.get(c,3),6)]
        if c==v: continue
        d=dict(decks); d[C]=[v if x==c else x for x in decks[C]]
        w=wr(d,f'{C}_{c}')[C]; n=decks[C].count(c)
        rows.append((base[C]-w,c,n))
        print(f'{C:9}{c:28} x{n} cost{cost.get(c)}  {base[C]-w:+5.1f}',flush=True)
    print('== sorted',C)
    for dlt,c,n in sorted(rows,reverse=True): print(f'   {c:28} x{n} {dlt:+5.1f}')
