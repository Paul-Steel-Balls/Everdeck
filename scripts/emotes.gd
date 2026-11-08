extends RefCounted
class_name Emotes

# The six emotes. The buttons show the short label; the Boss says it in
# their own words (the speech bubble) and acts it out on the board.

const IDS: Array = ["hey", "nice", "thanks", "whoa", "whoops", "bring"]

const LABELS: Dictionary = {
	"hey": "Hey!",
	"nice": "Nicely done",
	"thanks": "Thanks",
	"whoa": "Whoa!",
	"whoops": "Whoops",
	"bring": "Bring it",
}

const LINES: Dictionary = {
	"grunk": {
		"hey": "Oi! Smell that? That's fuse.",
		"nice": "Heh. Good boom.",
		"thanks": "Grunk owes you one. Small one.",
		"whoa": "Ooh! Do that again!",
		"whoops": "That was meant to explode.",
		"bring": "Grunk lights fuse. You run.",
	},
	"agatha": {
		"hey": "Hello, dearie! Have you eaten?",
		"nice": "Oh, well done, sweetheart.",
		"thanks": "Aren't you a dear.",
		"whoa": "Goodness gracious!",
		"whoops": "Oh, butter my biscuits.",
		"bring": "Grandma's getting the wooden spoon.",
	},
	"presto": {
		"hey": "Greetings! Pick a card. Any card.",
		"nice": "A trick worthy of the stage!",
		"thanks": "Much obliged. Truly.",
		"whoa": "Even I didn't see that coming!",
		"whoops": "...And that was part of the act.",
		"bring": "For my next trick, you disappear.",
	},
	"barnacle": {
		"hey": "Ahoy there, landlubber!",
		"nice": "Arr, fine sailin'.",
		"thanks": "Ye have me thanks, matey.",
		"whoa": "Shiver me timbers!",
		"whoops": "That be a slight miscalculation.",
		"bring": "Ready the cannons!",
	},
	"reginald": {
		"hey": "Well met, challenger.",
		"nice": "A noble stroke!",
		"thanks": "You have my gratitude.",
		"whoa": "By my sword!",
		"whoops": "A minor setback. Chivalry endures.",
		"bring": "Have at thee!",
	},
	"larry": {
		"hey": "Hey hey! Feelin' lucky?",
		"nice": "Nice roll, pal.",
		"thanks": "Appreciate ya, kid.",
		"whoa": "Jackpot!",
		"whoops": "House always wins. Usually.",
		"bring": "Let's raise the stakes.",
	},
}


static func line(class_id: String, id: String) -> String:
	var d: Dictionary = LINES.get(class_id, {})
	return str(d.get(id, LABELS.get(id, id)))
