"""Rename the player-facing game terms in card text and flavor:
hero -> Boss, minion -> Crew (member), spell -> Trick.
Only the words players read change; ids, types, effects and numbers stay."""
import json, re, sys
path = 'data/cards.json'
cards = json.load(open(path))
TEXT = [
    (r'\b(ALL|all) enemy minions\b', r'\1 enemy Crew'),
    (r'\b(ALL|all) friendly minions\b', r'\1 friendly Crew'),
    (r'\b(ALL|all) minions\b', r'\1 Crew'),
    (r'\bdamaged enemy minions\b', 'damaged enemy Crew'),
    (r'\benemy minions\b', 'enemy Crew'),
    (r'\bfriendly minions\b', 'friendly Crew'),
    (r'\bminions\b', 'Crew'),
    (r'\bMinions\b', 'Crew'),
    (r'\bminion\b', 'Crew member'),
    (r'\bMinion\b', 'Crew member'),
    (r'\bheroes\b', 'Bosses'),
    (r'\bhero\b', 'Boss'),
    (r'\bHero\b', 'Boss'),
    (r'\bspells\b', 'Tricks'),
    (r'\bspell\b', 'Trick'),
    (r'\bSpell\b', 'Trick'),
]
FLAVOR = {
    'agatha_sigh': ('Minions tremble.', 'Whole crews tremble.'),
    'presto_disint': ('It was a minion.', 'It was a Crew member.'),
    'barnacle_priestess': ('The tide is a minion.', 'The tide is Crew.'),
}
changed = 0
for c in cards:
    for f in ('text',):
        t = c.get(f, '')
        n = t
        for a, b in TEXT:
            n = re.sub(a, b, n)
        if n != t:
            c[f] = n
            changed += 1
    fl = c.get('flavor', '')
    if c['id'] in FLAVOR:
        a, b = FLAVOR[c['id']]
        fl = fl.replace(a, b)
    else:
        for a, b in TEXT:
            fl = re.sub(a, b, fl)
    if fl != c.get('flavor', ''):
        c['flavor'] = fl
        changed += 1
json.dump(cards, open(path, 'w'), indent=2, ensure_ascii=False)
print('fields changed', changed)
