extends RefCounted
class_name Emotes

# The six emote buttons. Every Boss has their own set: the button says it
# short, the Boss says it in full (the speech bubble) and acts it out
# (hop / nod / bow / startle / wobble / lunge). The six slot ids are what
# travels over the network; each side looks up the line for the Boss who
# said it.

const IDS: Array = ["hey", "nice", "thanks", "whoa", "whoops", "bring"]

# class -> six [button label, line, act], in IDS order.
const SETS: Dictionary = {
	"grunk": [
		["Oi!", "Oi! You. Yeah, you. Stand back.", "hey"],
		["Nice Crater", "Ooh. Nice crater.", "nice"],
		["Grunk's Fine", "Grunk's fine. Grunk's eyebrows less fine.", "thanks"],
		["Boom?", "...Was that the boom? That was the boom?", "whoa"],
		["Duck!", "DUCK!", "whoops"],
		["Light It!", "Light it! LIGHT IT!", "bring"],
	],
	"agatha": [
		["Hello, Dear", "Hello, dearie! Have you eaten?", "hey"],
		["Bless Your Heart", "Oh, bless your heart.", "nice"],
		["Have a Cookie", "Here, have a cookie. You look thin.", "thanks"],
		["Back in My Day", "Back in my day, we lost with dignity.", "whoa"],
		["Fiddlesticks", "Oh, fiddlesticks.", "whoops"],
		["Wooden Spoon", "Don't make me get the wooden spoon.", "bring"],
	],
	"presto": [
		["Ta-da!", "Ta-da! ...Hold for applause.", "hey"],
		["Bravo", "Bravo! You'd make a fine assistant.", "nice"],
		["Abracadabra", "Abracadabra! ...Abraca-DA-bra!", "thanks"],
		["Pick a Card", "Pick a card. Any card. Not that one.", "whoa"],
		["Part of the Act", "That was part of the act.", "whoops"],
		["Vanish!", "For my next trick, you disappear.", "bring"],
	],
	"barnacle": [
		["Ahoy!", "Ahoy there, landlubber!", "hey"],
		["Fine Sailin'", "Arr, fine sailin', matey.", "nice"],
		["Man Overboard", "Man overboard! ...Oh. That one's mine.", "thanks"],
		["Shiver Me Timbers", "Shiver me timbers!", "whoa"],
		["Walk the Plank", "Ye'll be walkin' the plank for that.", "whoops"],
		["Ready the Cannons", "Ready the cannons!", "bring"],
	],
	"reginald": [
		["Well Met", "Well met, challenger.", "hey"],
		["A Noble Stroke", "A noble stroke. I'll allow it.", "nice"],
		["For Honor", "For honor! And for the snacks after.", "thanks"],
		["By My Sword!", "By my sword!", "whoa"],
		["Minor Setback", "A minor setback. Chivalry endures.", "whoops"],
		["Have at Thee", "Have at thee!", "bring"],
	],
	"larry": [
		["Feelin' Lucky?", "Hey hey! Feelin' lucky?", "hey"],
		["Nice Roll", "Nice roll, pal.", "nice"],
		["Double or Nothing", "Double or nothing?", "thanks"],
		["Jackpot!", "JACKPOT!", "whoa"],
		["House Wins", "House always wins. Usually.", "whoops"],
		["Raise the Stakes", "Let's raise the stakes.", "bring"],
	],
}


static func _entry(class_id: String, id: String) -> Array:
	var i: int = IDS.find(id)
	var set: Array = SETS.get(class_id, SETS["grunk"])
	return set[i] if i >= 0 and i < set.size() else [id, id, id]


static func label(class_id: String, id: String) -> String:
	return str(_entry(class_id, id)[0])


static func line(class_id: String, id: String) -> String:
	return str(_entry(class_id, id)[1])


# How the Boss acts it out (a HoloUnit.emote_act name).
static func act(class_id: String, id: String) -> String:
	return str(_entry(class_id, id)[2])
