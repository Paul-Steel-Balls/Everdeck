# fieldeval.py PATCH FIELD.json -> each Boss's top-3 lists vs the others' top-3 (9 rotations), planner
import json,sys,subprocess,os,collections,itertools
P=os.path.dirname(os.path.abspath(__file__)); L='/home/claude/everdeck/lab/target/release/everdeck_lab'
patch,fieldf=sys.argv[1:3]; G=os.environ.get('G','200')
field=json.load(open(fieldf)); cls=sorted(field)
wr=collections.defaultdict(list); mu=collections.defaultdict(list); first=[]
tmp=f'{P}/fe_tmp'; os.makedirs(tmp,exist_ok=True)
for a in range(3):
  for b in range(3):
    d={c:[field[c][(a+b*i)%len(field[c])]] for i,c in enumerate(cls)}
    f=f'{tmp}/d{a}{b}.json'; json.dump(d,open(f,'w'))
    t=subprocess.run([L,'meta','--patch',patch,'--decks',f,'--games',G,'--seed',str(7+a*3+b),'--plan','4','--threads','2'],capture_output=True,text=True).stdout.splitlines()
    i=1
    while not t[i].startswith('going'):
        p=t[i].split(); wr[p[0]].append(float(p[1][:-1])); i+=1
    first.append(float(t[i].split()[2][:-1]))
    k=[j for j,l in enumerate(t) if l.startswith('row beats')][0]; names=t[k+1].split()
    for row in t[k+2:k+8]:
        p=row.split()
        for j,v in enumerate(p[1:]):
            if v!='-': mu[(p[0],names[j])].append(float(v[:-1]))
avg=lambda l:sum(l)/len(l)
print(' | '.join(f'{c} {avg(wr[c]):.1f}' for c in sorted(wr,key=lambda c:-avg(wr[c]))), f'| first {avg(first):.1f}')
bad=sorted((avg(v),k) for k,v in mu.items() if avg(v)<40)
print('  outside 60/40:', ', '.join(f'{a} v {b} {w:.0f}' for w,(a,b) in bad) or 'none')
if os.environ.get('OUT'):
    json.dump({'wr':{c:avg(v) for c,v in wr.items()},'mu':{f'{a}|{b}':avg(v) for (a,b),v in mu.items()},'first':avg(first)},open(os.environ['OUT'],'w'))
