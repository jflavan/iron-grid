class_name StoryCampaign
extends RefCounted

## The story mode's script: a linear list of chapters (prologue, twelve missions in three acts,
## epilogue). A "scene" chapter is portrait dialog only; a "mission" chapter is briefing dialog, a
## map (StoryMaps), mid-mission triggers (StoryDirector) and debrief dialog.
##
## Chapter keys: id, kind ("scene" / "mission"), act, title, synopsis, bg (cutscene backdrop id: a
## picture in assets/story/backdrops), and for scenes "lines"; for missions "map", "pre",
## "post", "post_bg", "triggers", "lose_if_lost", "win_if_down", "win_text", "second_wind" (pilots who
## get a second wind without being must-survive), "win_requires" (trigger id that must have fired
## before the map's own rules may award the victory).
## A dialog line is {"who": StoryCast id ("" = narrator), "text", optional "as": name shown instead}.

const ACT_1 := "ACT 1: THE IRON DIVISION"
const ACT_2 := "ACT 2: THE BLACK CLAW"
const ACT_3 := "ACT 3: IRON GHOST"

static var _chapters: Array[Dictionary] = []

static func chapters() -> Array[Dictionary]:
	if _chapters.is_empty():
		_chapters = _build()
	return _chapters

static func chapter(index: int) -> Dictionary:
	var list := chapters()
	return list[index] if index >= 0 and index < list.size() else {}

## Index of the chapter with this id, or -1.
static func index_of(id: String) -> int:
	var list := chapters()
	for i in list.size():
		if list[i]["id"] == id:
			return i
	return -1

## Data problems of the campaign, one message each (unknown speakers, bad maps, triggers naming
## pilots the mission never fields); empty when the script is well-formed.
static func validate() -> PackedStringArray:
	var errs := PackedStringArray()
	for ch in chapters():
		var id: String = ch["id"]
		var blocks: Array = [ch.get("lines", []), ch.get("pre", []), ch.get("post", [])]
		for t: Dictionary in ch.get("triggers", []):
			blocks.append(t.get("lines", []))
		for block: Array in blocks:
			for line: Dictionary in block:
				var who: String = str(line.get("who", ""))
				if who != "" and not StoryCast.has(who):
					errs.append("%s: unknown speaker '%s'" % [id, who])
				if str(line.get("text", "")) == "":
					errs.append("%s: empty dialog line" % id)
		if ch["kind"] != "mission":
			if (ch.get("lines", []) as Array).is_empty():
				errs.append("%s: scene has no lines" % id)
			continue
		var map: MapDefinition = ch.get("map")
		if map == null:
			errs.append("%s: mission has no map" % id)
			continue
		errs.append_array(map.validate(ChassisCatalog.story_ids()))
		var pilots: Dictionary = {}
		for sp in map.spawns:
			pilots[str(sp.get("pilot", ""))] = true
		for t: Dictionary in ch.get("triggers", []):
			for e: Dictionary in t.get("effects", []):
				for sp: Dictionary in e.get("spawn", []):
					pilots[str(sp.get("pilot", ""))] = true
				if e.has("rename"):
					pilots[str(e["rename"].get("to", ""))] = true
		var needed: Array = (ch.get("lose_if_lost", []) as Array).duplicate()
		if ch.has("win_if_down"):
			needed.append(ch["win_if_down"])
		for t: Dictionary in ch.get("triggers", []):
			if t.has("pilot"):
				needed.append(t["pilot"])
			if t.has("vs"):
				needed.append(t["vs"])
		for p: String in needed:
			if not pilots.has(p):
				errs.append("%s: refers to pilot '%s', who is not on the map" % [id, p])
	return errs

static func _l(who: String, text: String, shown_as: String = "") -> Dictionary:
	var line := {"who": who, "text": text}
	if shown_as != "":
		line["as"] = shown_as
	return line

static func _n(text: String) -> Dictionary:
	return {"who": "", "text": text}

static func _build() -> Array[Dictionary]:
	var maps: Dictionary = StoryMaps.build()
	var list: Array[Dictionary] = []

	# ====================================================================== PROLOGUE
	list.append({
		"id": "prologue", "kind": "scene", "act": "PROLOGUE", "title": "ASHES",
		"synopsis": "Fifteen years ago, a border village burned.",
		"bg": "village_fire",
		"lines": [
			_n("Fifteen years ago. The border village of Varnhalt, an hour before dawn."),
			_n("The Kriegs-Syndikat raid came down out of the hills without a declaration. By sunrise there was no village left to declare anything to."),
			_l("leon_child", "Mama? Mama, the roof is... Papa said he would come back. He said he would come BACK."),
			_n("The house folds in on itself. Through the smoke, on the ridge above the square, a walker stands and watches. Black plate. One red lens. It does not fire. It does not move."),
			_l("leon_child", "...why is it just standing there?"),
			_l("brann", "BOY! Out of that doorway! That beam is coming down whether you salute it or not!", "COALITION OFFICER"),
			_n("A very large man tears the door frame out of the wall with his hands, which is not how doors work, and carries the boy out under one arm."),
			_l("brann", "Colonel Brann Hammerfeld, 8th Iron Division. You got a name, soldier?", "COALITION OFFICER"),
			_l("leon_child", "...Leon."),
			_l("brann", "Leon what?"),
			_l("leon_child", "..."),
			_l("brann", "Hm. Well. Hammerfeld's a good name. Sturdy. You can borrow it till you find yours."),
			_n("The casualty list for Varnhalt ran to four hundred and twelve names. Every one of them was marked dead. One of them was wrong. Nobody yet knew it was two."),
		],
	})

	# ====================================================================== ACT 1
	list.append({
		"id": "m01", "kind": "mission", "act": ACT_1, "title": "PROVING GROUND ASCHEFELD",
		"synopsis": "A border raid, and a new squad that cannot stand each other.",
		"map": maps["m01"], "bg": "briefing_room", "post_bg": "field_camp",
		"lose_if_lost": ["leon"],
		"pre": [
			_n("Present day. Forward depot of the 8th Iron Division, Aschefeld sector."),
			_l("brann", "LISTEN UP! Two Syndikat raiders through the wire, heading for MY fuel. I have been awake since four doing one-armed push-ups and I am in a WONDERFUL mood. Hammerfeld! Your squad."),
			_l("leon", "...Sir."),
			_l("chad", "Sergeant Chad Brewster, volunteer, all the way from the States! You can call me 'Thunderhawk'. Or 'Big Rig'. I'm workshopping 'Thunder Rig'."),
			_l("mira", "I'm calling you a liability. Kessler, recon. I've read both your files. One of you doesn't talk and the other one doesn't stop. I honestly can't decide which is worse."),
			_l("leon", "..."),
			_l("mira", "It's you. It's definitely you. Say something!"),
			_l("leon", "The raiders will go for the crossroads depot first. We should already be moving."),
			_l("mira", "...Fine. That was a reasonable thing to say. Don't let it happen again."),
			_l("brann", "HA! They're bonding. Move out! Anyone who loses a walker arm-wrestles me for the paperwork!"),
		],
		"triggers": [
			{"on": "turn", "turn": 1, "lines": [
				_l("hq", "Signals to all walkers. Select a walker and pick a highlighted tile to move. Attack from an adjacent tile. Stand on a depot to take it."),
				_l("chad", "Copy that, Signals! Thunder Rig is rolling!"),
				_l("mira", "We are NOT calling him that."),
			]},
			{"on": "skirmish", "pilot": "leon", "lines": [
				_l("leon", "...Target in range. Engaging."),
				_l("mira", "He fights like he's apologising to it. Whatever. Covering your left, Hammerfeld. Not because I want to."),
			]},
			{"on": "skirmish", "pilot": "chad", "lines": [
				_l("chad", "FLAME ON, BABY! Somebody write down that I said that!"),
			]},
			{"on": "foes_left", "count": 1, "lines": [
				_l("mira", "One left. Try not to trip over it, Brewster."),
			]},
		],
		"post": [
			_l("chad", "Two raiders, zero problems! Did you SEE that? Did anybody see that? Leon. Buddy. You saw that."),
			_l("leon", "...I saw it."),
			_l("chad", "He SAW it!"),
			_l("mira", "You left the west depot wide open for a full minute. If Hammerfeld hadn't shifted over you'd be explaining a fuel fire to the General. ...That isn't a compliment, Hammerfeld. Stop looking at me."),
			_l("leon", "I wasn't."),
			_l("brann", "Not bad! Not GOOD. But not bad. Division moves on the Rhine-Fulda bridges at first light, and you three are going in the front. Dismissed! Leon. A word."),
			_l("brann", "You still check the ridgelines before you check the enemy. Every time."),
			_l("leon", "...Habit."),
			_l("brann", "Mm. It's been fifteen years, lad. That ridge is empty."),
		],
	})

	list.append({
		"id": "m02", "kind": "mission", "act": ACT_1, "title": "OPERATION: IRON BRIDGE",
		"synopsis": "The first real battle, for the Rhine-Fulda bridgeheads.",
		"map": maps["m02"], "bg": "briefing_room", "post_bg": "field_camp",
		"lose_if_lost": ["leon"],
		"pre": [
			_l("brann", "The Rhine-Fulda crossing! Two bridges, four bridgehead towns and one depot on the island in the middle. We hold the west bank. They hold the east. The island decides it."),
			_l("chad", "General, sir, request permission to take the island single-handed."),
			_l("brann", "Denied! ...Ask me again in a louder voice."),
			_l("chad", "REQUEST PERMISSION TO TAKE THE ISLAND SINGLE-HANDED, SIR!"),
			_l("brann", "STILL DENIED! But I respect it."),
			_l("mira", "If he charges the island, somebody has to sit on the south bridgehead or we lose it. And it won't be him, so it'll be me. It's always me."),
			_l("leon", "I'll take the north bridge. Kessler, the centre ford is yours if you want it. The Falke wades."),
			_l("mira", "I know it wades, I fly it! ...The centre ford. Fine. Good call. Shut up."),
		],
		"triggers": [
			{"on": "turn", "turn": 2, "lines": [
				_l("chad", "Okay, so, funny story, I may have left the south bridgehead a LITTLE bit empty. It was right there! The enemy was right THERE!"),
				_l("mira", "You absolute... Kessler to Signals, I am covering South West Bridgehead. AGAIN. Hammerfeld, this is your squad, so this is your fault."),
				_l("leon", "...Understood."),
				_l("mira", "Don't just AGREE with me!"),
			]},
			{"on": "capture", "pos": Vector2i(4, 4), "owner": 0, "lines": [
				_l("hq", "Signals confirms Coalition colours on the Central Island Depot. Hold it through their turn and the crossing is ours."),
			]},
			{"on": "capture", "pos": Vector2i(4, 4), "owner": 1, "lines": [
				_l("hq", "Signals to all walkers: the Syndikat has the island depot. Take it back or we lose the crossing."),
			]},
		],
		"post": [
			_l("brann", "The crossing is OURS! Brewster! You abandoned a bridgehead."),
			_l("chad", "...Yes, sir."),
			_l("brann", "Kessler held it with a recon strider and bad language. Buy her a drink. Kessler! You blamed your squad leader on an open channel."),
			_l("mira", "It WAS his fault. Technically. Structurally."),
			_l("leon", "She was right to hold it. I should have assigned it before we moved."),
			_l("mira", "...You're not supposed to take my side when I'm yelling at you. It's very annoying."),
			_l("hq", "General. Forward observers report a second Syndikat column moving on Citadel Höhenburg. Heavy walkers. And, sir... a unit standard we haven't seen on this front. A black claw on a red field."),
			_l("brann", "...The Black Claw. So he's finally come down off his mountain. Everybody up! We are going to Höhenburg, and we are getting there first."),
		],
	})

	list.append({
		"id": "m03", "kind": "mission", "act": ACT_1, "title": "BASTION REDOUBT",
		"synopsis": "Hold Citadel Höhenburg. The Black Claw takes the field.",
		"map": maps["m03"], "bg": "briefing_room", "post_bg": "field_camp",
		"lose_if_lost": ["leon"],
		"pre": [
			_l("brann", "Citadel Höhenburg! Four strongpoints on a plateau. They have five walkers coming up the valley and one of them is a Black Claw artillery ace. We hold till the Division arrives. Eight turns."),
			_l("leon", "The Black Claw. Who commands it?"),
			_l("brann", "Calls himself Wolfram. Wears a mask. Trained every pilot in that corps personally, and nobody has ever beaten him in a duel. And he never fights a battle he hasn't already watched."),
			_l("chad", "A mask? Okay, that's kind of cool. I'm not saying it's cool. It's cool."),
			_l("mira", "Their ace is Commander Ilse Rotmann. Spinne pilot. Forty-one confirmed. She sends flowers to the families."),
			_l("chad", "...That's nice?"),
			_l("mira", "She sends them BEFORE."),
			_l("brann", "I'm on the north gate. I will be fighting shirtless, as is my right as a general. Hold your ground and let them climb!"),
		],
		"triggers": [
			{"on": "turn", "turn": 2, "lines": [
				_n("On the far ridge, above the valley road, a single walker has not moved since the battle began. Black plate. One red lens."),
				_l("leon", "...That ridge. There's something on that ridge."),
				_l("mira", "Eyes front, Hammerfeld! The ones climbing the hill are the ones shooting at us!"),
			]},
			{"on": "skirmish", "pilot": "ilse", "lines": [
				_l("ilse", "Ara... a Coalition walker that doesn't flinch. How rude. Everybody flinches for me."),
			]},
			{"on": "skirmish", "pilot": "ilse", "vs": "leon", "lines": [
				_l("ilse", "You. The grey Sturmjäger. You fight like someone who's already lost everything. I LIKE that. What's your name?"),
				_l("leon", "..."),
				_l("ilse", "Oh, he won't even TELL me. That's fine. I'll find out. I always find out."),
			]},
			{"on": "hull", "pilot": "ilse", "below": 35, "lines": [
				_l("ilse", "My Spinne... you broke my Spinne. Nobody has ever... ahaha. Ahahaha! Grey Sturmjäger. I'm going to remember the sound of your engine for the REST OF MY LIFE."),
				_l("chad", "Uh. Leon? I think you made a friend."),
				_l("mira", "That is NOT a friend. That is a restraining order with a rocket pod!"),
			], "effects": [{"withdraw": {"pilot": "ilse"}}]},
		],
		"post": [
			_l("brann", "HÖHENBURG STANDS! And I didn't even get to use my left arm!"),
			_l("hq", "General, the walker on the ridge. It is withdrawing. It never fired a shot."),
			_l("wolfram", "...So that is the 8th Iron's new spearhead. The grey Sturmjäger never once looked at its own flank. It only looked up here. Interesting."),
			_l("ilse", "Commander Wolfram, sir! Request permission to be assigned to that sector permanently. Forever. Until one of us is dead."),
			_l("wolfram", "Denied, Rotmann. You lost."),
			_l("ilse", "I KNOW. Isn't it WONDERFUL?"),
			_l("leon", "It was the same. The same walker. The same ridge."),
			_l("mira", "Hammerfeld? ...Hey. You're shaking. Leon."),
			_l("leon", "I'm fine."),
			_l("mira", "You're obviously not, you idiot. ...I'm not asking because I care. A squad leader who shakes is a tactical problem."),
		],
	})

	# ====================================================================== ACT 2
	list.append({
		"id": "m04", "kind": "mission", "act": ACT_2, "title": "BREAKTHROUGH AT KESSEL-9",
		"synopsis": "Take the Black Claw's headquarters bunker, and what is inside it.",
		"map": maps["m04"], "bg": "briefing_room", "post_bg": "records_room",
		"lose_if_lost": ["leon"],
		"pre": [
			_l("brann", "Kessel-9! Rail nexus, and the Black Claw's field headquarters. Their files are in that bunker: rosters, routes, who Wolfram actually is under the tin face. I want the bunker and I want the filing cabinets. In that order!"),
			_l("leon", "I'll take the bunker."),
			_l("brann", "You'll take it WITH your squad, at the speed of your squad."),
			_l("leon", "...Sir."),
			_l("chad", "Spearhead, baby! Callsign 'Spear Daddy'."),
			_l("mira", "No."),
			_l("chad", "'Spear Uncle'."),
			_l("mira", "Brewster, I will shoot you myself and write it up as weather."),
		],
		"triggers": [
			{"on": "capture", "pos": Vector2i(8, 3), "owner": 0, "id": "hq", "lines": [
				_l("leon", "I'm in the bunker. There's a safe. It's open. They left in a hurry."),
			]},
			{"on": "capture", "pos": Vector2i(8, 4), "owner": 0, "unless_fired": "hq", "id": "hq", "lines": [
				_l("leon", "We have the bunker. There's a records room. Somebody tried to burn it and ran out of time."),
			]},
		],
		"post": [
			_n("Kessel-9 command bunker. A records room, half burned."),
			_l("mira", "Personnel files. Black Claw officer roster, the real one. Hammerfeld, hold the lamp. ...'Wolfram: assumed name. See annex.'"),
			_l("mira", "'Varga, Konrad. Formerly Major, Coalition Military Intelligence. Defected fifteen years ago, following the Varnhalt action. Listed by the Coalition as killed at Varnhalt, with wife and son.'"),
			_l("leon", "..."),
			_l("chad", "Whoa. So the scary mask guy is one of OURS? That's messed up. Right? Leon? ...Leon, buddy?"),
			_l("leon", "Varnhalt had four hundred and twelve people in it. I can still tell you which house was the baker's."),
			_l("mira", "...You're from Varnhalt."),
			_l("leon", "My mother was Anna Varga. She died under a roof beam. I was seven. And my father... went out the night before. He said he'd come back."),
			_l("leon", "He was on the ridge. He was on the RIDGE. He stood there in that walker and he WATCHED."),
			_l("mira", "Leon..."),
			_l("leon", "Don't. Tell the General the files are secure. And tell him I know why he never asked me my real name."),
			_n("Konrad Varga was alive. The quiet went out of Leon Hammerfeld that night, and something else moved in."),
		],
	})

	list.append({
		"id": "m05", "kind": "mission", "act": ACT_2, "title": "PURSUIT AT RAVENSFURT",
		"synopsis": "Leon stops waiting for orders.",
		"map": maps["m05"], "bg": "motor_pool", "post_bg": "field_camp",
		"lose_if_lost": ["leon"],
		"pre": [
			_l("hq", "Lieutenant Hammerfeld, Division orders are to hold at Kessel-9 until the heavy walkers come up. Acknowledge."),
			_l("leon", "There's a Black Claw detachment at the Ravensfurt rail yard. They're loading out. If they get on that train they're gone."),
			_l("hq", "Lieutenant, that is not an acknowledgement."),
			_l("leon", "No. It isn't."),
			_l("mira", "He's already walking. Unbelievable! Brewster, get in your walker."),
			_l("chad", "We're following him? Against orders? ...Awesome. I mean: terrible. Awesome."),
			_l("mira", "Somebody has to keep him alive long enough to be court-martialled."),
		],
		"triggers": [
			{"on": "turn", "turn": 1, "lines": [
				_l("leon", "Black Claw walkers, this is Lieutenant Hammerfeld. Where is Wolfram?"),
				_l("syndikat", "Coalition pilot on our band. ...You're the grey Sturmjäger. The Commander said you'd come. He said you'd come too fast.", "BLACK CLAW OFFICER"),
			]},
			{"on": "skirmish", "pilot": "leon", "lines": [
				_l("leon", "WHERE IS HE?"),
				_l("mira", "Leon, your flank! You are a squad leader, not a battering ram! ...Ugh. Covering. AGAIN."),
			]},
			{"on": "foes_left", "count": 1, "lines": [
				_l("chad", "One left! Hey, Leon, maybe leave this one able to talk? For, like, questions?"),
			]},
		],
		"post": [
			_l("leon", "He wasn't here."),
			_l("mira", "No, he wasn't. A rail yard and four walkers. That's what you disobeyed Division for."),
			_l("leon", "One of them knew my walker. He's been telling them about me."),
			_l("chad", "Okay, real talk? That's not a good thing, man. That's the guy studying you."),
			_l("hq", "Lieutenant Hammerfeld. The General wants to see you. He said, and I am quoting, 'tell the boy to bring his own chair, because he will be sitting down for a WHILE.'"),
			_l("leon", "Tell him I'm busy. Their walkers were built at the Eisenhammer foundry. That's where the next ones come from."),
			_l("mira", "Leon. LEON! ...He's not even hearing me. Why do I bother? Why do I KEEP bothering?"),
		],
	})

	list.append({
		"id": "m06", "kind": "mission", "act": ACT_2, "title": "THE EISENHAMMER FOUNDRY",
		"synopsis": "A raid on the Black Claw's armour works, with unwanted help.",
		"map": maps["m06"], "bg": "motor_pool", "post_bg": "office",
		"lose_if_lost": ["leon"],
		"pre": [
			_l("mira", "For the record, this is the second unauthorised operation in a week, and I am only here to file the complaint afterwards."),
			_l("chad", "Same! I am here ironically."),
			_l("leon", "The foundry builds his walkers. Take the works and the Black Claw stops growing. He'll have to come and stop me himself."),
			_l("mira", "'Stop ME.' Not 'stop us'. You hear yourself?"),
			_l("ilse", "Hellooo, grey Sturmjäger! I can hear your engine from here. You came all this way to see me? You shouldn't have. You REALLY shouldn't have."),
			_l("chad", "Oh no. It's the flowers lady."),
			_l("ilse", "I've been assigned to defend this foundry. Isn't that sweet of them? They think I'm going to let somebody ELSE have you."),
		],
		"triggers": [
			{"on": "turn", "turn": 2, "lines": [
				_l("ilse", "Klaue-One, you're standing between me and my Sturmjäger. That's very inconsiderate."),
				_l("syndikat", "Commander Rotmann, what are you... that's OUR grid! CHECK FIRE! CHECK FIRE!", "BLACK CLAW OFFICER"),
				_l("ilse", "Oops."),
			], "effects": [{"friendly_fire": {"near": "leon", "amount": 38}}]},
			{"on": "turn", "turn": 4, "lines": [
				_l("ilse", "Nobody touches him but me. NOBODY. Fire mission, my own front line, danger close. Ehehe."),
				_l("mira", "She's shelling her own side. She is actually shelling her own side for him. Leon, I want it on record that I hate everything about your life."),
			], "effects": [{"friendly_fire": {"near": "leon", "amount": 38}}]},
			{"on": "skirmish", "pilot": "ilse", "vs": "leon", "lines": [
				_l("ilse", "FINALLY! Look at me. Look only at me!"),
				_l("leon", "You're in my way."),
				_l("ilse", "...He's so COLD. I'm going to faint."),
			]},
			{"on": "hull", "pilot": "ilse", "below": 35, "lines": [
				_l("ilse", "Twice! You've broken me TWICE! We have to stop meeting like this. No we don't. See you soon, my Sturmjäger!"),
			], "effects": [{"withdraw": {"pilot": "ilse"}}]},
		],
		"post": [
			_l("brann", "LIEUTENANT."),
			_l("leon", "General. The foundry is..."),
			_l("brann", "I did not ask about the foundry! I asked you to hold at Kessel-9. Twice now you have taken MY walkers and MY pilots off to settle YOUR account. Give me your ignition key."),
			_l("leon", "...Sir. He was on the ridge. You were THERE. You pulled me out and you knew, you've known for years who..."),
			_l("brann", "I knew a boy needed a name more than he needed a grudge! Key. NOW. You're grounded, Leon. Not as punishment. Because the next time you go out like this, you don't come back, and I am too old to bury you."),
			_l("leon", "..."),
			_n("Leon puts the key on the table and walks out. Mira catches him in the corridor."),
			_l("mira", "Hey. HEY. Don't you walk away from me, Hammerfeld, I ran here!"),
			_l("mira", "I've covered your flank on every sortie since Aschefeld. Every single one. Do you think that's because it's my JOB? There are four other flanks in this squad! I don't even like Brewster's flank!"),
			_l("leon", "Kessler..."),
			_l("mira", "It's not like I... I just don't want you to die, all right?! Stupid. That's all. Don't read into it. If you read into it I'll kill you myself."),
			_l("leon", "...Thank you, Mira."),
			_l("mira", "D-don't use my first name! ...You can use it a little."),
		],
	})

	list.append({
		"id": "m07", "kind": "mission", "act": ACT_2, "title": "THE TAUBER CAUSEWAY",
		"synopsis": "The squad has to fall back. Somebody has to stay on the bridge.",
		"map": maps["m07"], "bg": "field_camp", "post_bg": "causeway",
		"lose_if_lost": ["chad"],
		"pre": [
			_n("The Black Claw answered the foundry raid within the week. The squad was caught east of the Tauber with two walkers on tow cables and Leon riding in the recovery truck."),
			_l("mira", "They're twenty minutes behind us and we're towing half the squad. We don't make the Division line. Not all of us."),
			_l("leon", "Give me a walker. Any walker."),
			_l("mira", "You're grounded and your Sturmjäger is in pieces on a flatbed!"),
			_l("chad", "Hey. There's a fort on the causeway. One road in. A Brenner could sit on that all day."),
			_l("mira", "Brewster, that isn't funny."),
			_l("chad", "Not joking. Look, I talk a lot. I know I talk a lot. You know why a guy crosses an ocean to join somebody else's war? ...Me neither, honestly. But I'm here, and that bridge is right there, and I am REALLY good at standing in one place being loud."),
			_l("leon", "Chad."),
			_l("chad", "Go on. Get 'em home, Leon. That's an order. Can a sergeant give a lieutenant an order? I'm doing it anyway."),
		],
		"triggers": [
			{"on": "turn", "turn": 1, "lines": [
				_l("chad", "Okay. Okay okay okay. Just me. Just Big Rig. Stay on the fort, dig in with R, let 'em come up out of the water."),
				_l("chad", "...Nobody's on the channel. I can say it. I'm scared out of my mind. Cool. Great. Let's go."),
			]},
			{"on": "turn", "turn": 3, "lines": [
				_l("syndikat", "Pursuit group, the causeway is held by ONE walker. Go around it, go over it, I don't care. Second wave, move up!", "SYNDIKAT OFFICER"),
				_l("chad", "More of you? Sure! Plenty of bridge for everybody!"),
			], "effects": [{"spawn": [
				{"chassis": "falke", "callsign": "HATZ-3 (Spähfalke)", "pos": Vector2i(0, 2), "faction": 1},
			]}]},
			{"on": "turn", "turn": 4, "lines": [
				_l("chad", "Hey, Syndikat! You know what we call this back home? Me neither! I never did anything like this back home!"),
			], "effects": [{"spawn": [
				{"chassis": "moloch", "callsign": "HATZ-4 (Brenner)", "pos": Vector2i(0, 2), "faction": 1},
			]}]},
			{"on": "hull", "pilot": "chad", "below": 40, "lines": [
				_l("chad", "Armour's going. That's fine. That's what it's FOR. Not one of you gets past this fort. Not one!"),
			]},
			{"on": "turn", "turn": 6, "lines": [
				_l("hq", "Signals to Brewster. The squad is across the Division line. All of them. Sergeant, do you copy? ...Sergeant?"),
				_l("chad", "...Copy, Signals. One more turn. Then I'm coming home."),
			]},
		],
		"post": [
			_n("Division lines, the next morning. A Brenner with no paint left on it walks in under its own power."),
			_l("mira", "You IDIOT! You stupid, loud, enormous IDIOT! ...You're alive. Good. Fine. I wasn't worried."),
			_l("leon", "Chad. What you did on that bridge..."),
			_l("chad", "Whoa, whoa, hey. Nope. We're not doing that."),
			_l("leon", "You held a causeway alone against five..."),
			_l("chad", "DID I? Don't remember. Total blank. Anyway! Who's hungry? I'm thinking callsign 'Bridge Daddy'."),
			_l("mira", "...Brewster."),
			_l("chad", "Yeah?"),
			_l("mira", "...'Big Rig' is fine. You can have 'Big Rig'."),
			_l("chad", "YES! She SAID it! Leon, you heard her, she SAID it!"),
			_l("brann", "Sergeant Brewster. My office. Bring your arm. You have EARNED the right to lose to me personally."),
		],
	})

	list.append({
		"id": "m08", "kind": "mission", "act": ACT_2, "title": "WOLF'S PASS",
		"synopsis": "Leon finally meets Wolfram on the field.",
		"map": maps["m08"], "bg": "motor_pool", "post_bg": "snow_pass",
		"second_wind": ["leon"],
		"pre": [
			_n("03:40. The motor pool. A rebuilt grey Sturmjäger, and a spare ignition key that the General left on his desk in plain sight."),
			_l("leon", "He left it out. He wanted me to choose."),
			_l("mira", "And you're choosing wrong. Wolfram is sitting in that pass with two escorts like he's waiting for a train. It's an invitation, Leon."),
			_l("leon", "Then I'm accepting it. You don't have to come."),
			_l("mira", "Obviously I'm coming! Somebody has to watch you lose."),
			_l("chad", "Big Rig is ALSO coming. For moral support and fire."),
			_l("leon", "...Thank you. Both of you."),
			_l("mira", "Don't thank me. Just for once, look at your flank."),
		],
		"triggers": [
			{"on": "turn", "turn": 1, "lines": [
				_l("wolfram", "Grey Sturmjäger. You broke my foundry, my rail line and my best gunner's composure. I have been curious about you for some time."),
				_l("leon", "Wolfram."),
				_l("wolfram", "You say it like a man with a claim on it. Very well. Come and show me what the 8th Iron has been building."),
			]},
			{"on": "skirmish", "pilot": "wolfram", "vs": "leon", "lines": [
				_l("leon", "Fifteen years! FIFTEEN YEARS!"),
				_l("wolfram", "You fight angry. Your stance is good. Your instincts are excellent. Somebody taught you to check a ridgeline. But anger makes you early. Watch."),
			]},
			{"on": "down", "pilot": "leon", "id": "end", "lines": [
				_n("The Sturmjäger goes down with its leg gone at the knee. Before the dust settles the black Kaiserstuhl is standing over it. It levels its gun at the cockpit, and holds."),
				_l("wolfram", "...No."),
				_l("syndikat", "Commander? He's helpless. Finish it!", "BLACK CLAW OFFICER"),
				_l("wolfram", "I said no. ...I don't know why. Withdraw. All units. We are done here."),
			], "effects": [{"win": "The Sturmjäger went down in the pass. Wolfram had the shot, and did not take it.",
				"title": "OPERATION ABORTED // WOLFRAM HOLDS THE PASS"}]},
			{"on": "hull", "pilot": "wolfram", "below": 50, "unless_fired": "end", "id": "end", "lines": [
				_l("wolfram", "You've marked my armour. Nobody has done that in ten years. ...So I will stop teaching."),
				_n("It is over in four seconds. The Sturmjäger is on its back with its leg gone, and a gun is levelled at its cockpit. And holds."),
				_l("wolfram", "...No. Not this one. I don't know why. Withdraw. All units."),
			], "effects": [{"win": "They hurt him. Then Wolfram stopped holding back, and the Sturmjäger went down. He did not take the shot.",
				"title": "OPERATION ABORTED // WOLFRAM HOLDS THE PASS"}]},
			{"on": "turn", "turn": 6, "unless_fired": "end", "id": "end", "lines": [
				_l("wolfram", "You've kept me waiting, grey Sturmjäger. I'll come to you."),
				_n("The black Kaiserstuhl crosses the pass faster than a command walker should be able to move. One exchange. The Sturmjäger is on its back with its leg gone, and a gun is levelled at its cockpit. And holds."),
				_l("wolfram", "...No. Not this one. I don't know why. Withdraw. All units."),
			], "effects": [{"win": "Wolfram came down the pass himself. The Sturmjäger lasted one exchange. He did not take the shot.",
				"title": "OPERATION ABORTED // WOLFRAM HOLDS THE PASS"}]},
		],
		"post": [
			_n("Wolf's Pass. Snow coming down on a grey walker lying on its side."),
			_l("mira", "Leon! LEON! Open the hatch, you idiot, open the... he's breathing. He's breathing. Oh, thank god. I mean. Good. Tactically."),
			_l("leon", "He had me. He had the shot and he just... stood there. Like the ridge. He stood there and WATCHED."),
			_l("chad", "Buddy, he let you go. Scary mask guy let you GO. Why would he do that?"),
			_l("leon", "I don't know. He doesn't know who I am. I never said it. I had him in front of me and I couldn't say my own name."),
			_l("wolfram", "...Rotmann. The pilot of the grey Sturmjäger. What do we know about him?"),
			_l("ilse", "Lieutenant Leon Hammerfeld! Adopted son of General Hammerfeld, twenty-two, blood type A, hates mornings. Why, Commander? You can't have him. I saw him first."),
			_l("wolfram", "Hammerfeld. ...No. Nothing. For a moment the way he set his feet reminded me of someone. A long time ago."),
			_n("Three weeks later, with Black Claw strength bled white at Ravensfurt and Eisenhammer, the Coalition offensive opened along the whole front. The 8th Iron Division marched on the capital."),
		],
	})

	# ====================================================================== ACT 3
	list.append({
		"id": "m09", "kind": "mission", "act": ACT_3, "title": "THE KAISERWALL",
		"synopsis": "The march on the capital. Old Iron leads from the front.",
		"map": maps["m09"], "bg": "briefing_room", "post_bg": "capital_street",
		"lose_if_lost": ["leon"],
		"pre": [
			_l("brann", "THE KAISERWALL! The Syndikat says no army has breached it in two hundred years. I say no army has had ME. I am leading this one from the front, in my Siegebreaker, with my shirt OFF."),
			_l("hq", "General, the staff strongly advises..."),
			_l("brann", "The staff may arm-wrestle me about it! Leon. You're back on the line. Why?"),
			_l("leon", "...Because the squad nearly died following me to a fight I picked. And because he beat me, and I'm still here. I don't know what that means yet. I want to find out with the Division, not without it."),
			_l("brann", "HA! That's the first sensible thing you've said since Kessel-9. Here's your key. The real one."),
			_l("mira", "He's listening to orders. It's unnatural. I don't trust it. ...I'm glad. Shut up."),
			_l("chad", "Big Rig, reporting for wall removal!"),
		],
		"triggers": [
			{"on": "skirmish", "pilot": "brann", "lines": [
				_l("brann", "I HAVE WAITED TWO HUNDRED YEARS FOR THIS! ...Figuratively! I am sixty-one!"),
			]},
			{"on": "capture", "pos": Vector2i(5, 3), "owner": 0, "id": "gate", "lines": [
				_l("hq", "Signals confirms Coalition colours on the Main Gate. The wall is breached. Push for Wall Command!"),
			]},
			{"on": "capture", "pos": Vector2i(5, 4), "owner": 0, "unless_fired": "gate", "id": "gate", "lines": [
				_l("hq", "Signals confirms Coalition colours on the Main Gate. The wall is breached. Push for Wall Command!"),
			]},
			{"on": "hull", "pilot": "brann", "below": 40, "lines": [
				_l("leon", "General, fall back! Your armour is..."),
				_l("brann", "My armour is DECORATIVE, boy! The muscle underneath is structural!"),
			]},
		],
		"post": [
			_l("brann", "Two hundred years! Gone in an afternoon! Somebody paint my name on that gate. Large."),
			_l("mira", "The government quarter is next. Then the Eisenthron itself. Grau's fortress."),
			_l("leon", "And the Black Claw in front of it."),
			_l("brann", "Leon. When you meet him again. What are you going to do?"),
			_l("leon", "...I'm going to say my name. The real one. I'm going to make him hear it. After that, I don't know."),
			_l("brann", "Good. A man should know who's shooting at him. Get some sleep. All of you! That is an ORDER, Kessler, stop cleaning his optics for him."),
			_l("mira", "I w-wasn't! They were dirty! It's a squad readiness issue!"),
		],
	})

	list.append({
		"id": "m10", "kind": "mission", "act": ACT_3, "title": "CROWN BOULEVARD",
		"synopsis": "Street fighting in the capital, and Ilse makes up her mind.",
		"map": maps["m10"], "bg": "briefing_room", "post_bg": "capital_street",
		"win_requires": "defect",
		"lose_if_lost": ["leon"],
		"pre": [
			_l("brann", "The government quarter! Five strongpoints. Crown Plaza in the middle. Take the plaza and the rest falls over."),
			_l("hq", "General, we're picking up a transmission on the open band. It's been repeating for an hour. It is... addressed to Lieutenant Hammerfeld."),
			_l("ilse", "...and ANOTHER thing, my Sturmjäger, they've put me on the east side with a garrison of perfectly dull men, and Marshal Grau has ordered that you be killed on sight by 'any available unit'. ANY available unit! As if you were just ANYBODY'S!"),
			_l("chad", "She's been doing this for an HOUR?"),
			_l("mira", "I'm going to shoot her. Leon, I'm going to shoot her first, and I want that understood."),
			_l("leon", "...She shelled her own side for us at the foundry. Twice."),
			_l("mira", "For YOU! Not 'us'! Don't you dare be reasonable about her!"),
		],
		"triggers": [
			{"on": "skirmish", "pilot": "ilse", "vs": "leon", "id": "defect", "lines": [
				_l("ilse", "There you are. Third time. I've thought about this every night. Now hold still and let me..."),
				_l("leon", "Rotmann. Grau ordered me killed by anyone. You'd be doing it for him."),
				_l("ilse", "...For HIM. For that grey old man in his big ugly walker. He gave you away like a ration card."),
				_l("ilse", "No. No, no, no. If the Syndikat wants you dead, then I don't want the Syndikat. It's very simple. I don't know why I didn't see it before."),
				_l("ilse", "Garrison, this is Commander Rotmann. I am changing my fire mission. To you. Ehehe!"),
				_l("mira", "She's DEFECTING? For HIM? Oh, come ON!"),
			], "effects": [{"cancel_skirmish": true}, {"convert": {"pilot": "ilse"}}]},
			{"on": "turn", "turn": 3, "unless_fired": "defect", "id": "defect", "lines": [
				_l("syndikat", "All units, Marshal's order stands: the grey Sturmjäger is priority one. Rotmann, you have the range. Fire!", "GARRISON COMMANDER"),
				_l("ilse", "...You want ME to kill him because a grey old man in a big ugly walker said so? He gave my Sturmjäger away like a ration card."),
				_l("ilse", "No. If the Syndikat wants him dead, then I don't want the Syndikat. It's very simple. I don't know why I didn't see it before."),
				_l("ilse", "Garrison, this is Commander Rotmann. I am changing my fire mission. To you. Ehehe!"),
				_l("mira", "She's DEFECTING? For HIM? Oh, come ON!"),
			], "effects": [{"convert": {"pilot": "ilse"}}]},
			{"on": "hull", "pilot": "ilse", "below": 50, "unless_fired": "defect", "id": "defect", "lines": [
				_l("ilse", "You hit me. Your SQUAD hit me. And my own garrison just sat there and let it happen, because the Marshal only cares who kills the Sturmjäger."),
				_l("ilse", "I don't want to be on a side that gives him away like a ration card. Garrison, this is Commander Rotmann. I am changing my fire mission. To you. Ehehe!"),
				_l("mira", "She's DEFECTING? For HIM? Oh, come ON!"),
			], "effects": [{"convert": {"pilot": "ilse"}}]},
			{"on": "capture", "pos": Vector2i(4, 3), "owner": 0, "lines": [
				_l("hq", "Signals confirms Coalition colours on Crown Plaza. Hold it!"),
			]},
		],
		"post": [
			_l("brann", "The quarter is ours! And we appear to have acquired... a Syndikat artillery commander."),
			_l("ilse", "Commander Ilse Rotmann, formerly of the Black Claw, requesting asylum, a parking space next to the grey Sturmjäger, and his blood type confirmed in writing."),
			_l("mira", "Absolutely not! General, she is a war criminal with a crush!"),
			_l("brann", "She's also the best gunner on the continent and she knows the Eisenthron's fire plan. Welcome to the 8th Iron, Commander. If you shell my boy I will fold your walker in half."),
			_l("ilse", "Understood, Father."),
			_l("brann", "Do NOT call me that."),
			_l("ilse", "My Sturmjäger. A warning, because I like you alive. Wolfram is waiting at the Throne Gate. He isn't there for Grau. He asked for that post himself. He's waiting for YOU."),
			_l("leon", "...I know. I'm going to him."),
		],
	})

	list.append({
		"id": "m11", "kind": "mission", "act": ACT_3, "title": "GATE OF THE EISENTHRON",
		"synopsis": "Leon and Wolfram, at the gate of Grau's fortress.",
		"map": maps["m11"], "bg": "capital_street", "post_bg": "throne_gate",
		"win_requires": "reveal",
		"lose_if_lost": ["leon"],
		"pre": [
			_l("brann", "The Eisenthron. Grau's fortress. The Black Claw holds the road, the Marshal's Garde holds the gate. Last one, children. Then we all go home."),
			_l("leon", "General. Wolfram is mine. Not to kill. To face."),
			_l("brann", "I know, lad. I've known since the night I gave you my name. Go and get yours back."),
			_l("mira", "Leon. Whatever happens out there. You... you'd better come back, all right? I didn't cover your flank for a year so you could die at the last gate."),
			_l("leon", "I'll come back, Mira. I promise. ...I'm not him."),
			_l("chad", "Big Rig's got your other flank, buddy. And the crazy lady's got, uh. The sky?"),
			_l("ilse", "I have the range on everyone. Always. Ehehe."),
		],
		"triggers": [
			{"on": "turn", "turn": 1, "lines": [
				_l("wolfram", "Grey Sturmjäger. You came back. I had hoped you would. I have been training my corps against the memory of you for a month."),
				_l("leon", "I came back to tell you something. Wait for me there."),
			]},
			{"on": "skirmish", "pilot": "wolfram", "vs": "leon", "id": "reveal", "lines": [
				_l("wolfram", "Your stance has changed. You're not early any more. Who ARE you?"),
				_l("leon", "The village was called Varnhalt. The house was the third one past the baker's. The roof beam came down on my mother. Her name was Anna. ANNA VARGA."),
				_l("wolfram", "..."),
				_l("leon", "I was seven. My father went out the night before and he said he'd come back. I stood in the doorway and I saw his walker on the ridge. It didn't fire. It didn't MOVE."),
				_l("wolfram", "...Leon?"),
				_n("The black Kaiserstuhl lowers its gun. A hand comes up to the mask, and the mask comes off."),
				_l("konrad", "They told me the house was empty. They told me you were both already... I read your name on the list. I read it four hundred and twelve times."),
				_l("konrad", "I have been training the finest corps in the Syndikat to kill the Coalition's finest pilot. And it was you. It was you the whole time. Oh, my boy."),
				_l("leon", "Why. Just tell me WHY."),
				_l("konrad", "Because Grau cannot be reached by an army. Only by a man he trusts. I let Varnhalt burn so he would trust me. I let your mother... I have carried one bullet for fifteen years, Leon, and I have been waiting to stand close enough to use it."),
				_l("konrad", "Black Claw! All units! The standard turns. Our enemy is in that fortress, and he always was. With the grey Sturmjäger: FORWARD!"),
				_l("grau", "Varga. So. Fifteen years, and you open your hand at the last gate. Garde. Kill them all. The traitor first."),
			], "effects": [
				{"cancel_skirmish": true},
				{"spawn": StoryMaps.throne_gate_reinforcements()},
				{"convert": {"group": "claw"}},
				{"rename": {"pilot": "wolfram", "to": "konrad", "callsign": "KONRAD (Kaiserstuhl)"}},
				{"plot_armor": {"pilot": "konrad", "value": 1}},   # he has to be standing at the gate when it falls
			]},
			{"on": "hull", "pilot": "wolfram", "below": 55, "unless_fired": "reveal", "id": "reveal", "lines": [
				_l("wolfram", "Enough. Grey Sturmjäger! Your squad fights like you. Before this ends: who ARE you?"),
				_l("leon", "The village was called Varnhalt. The house was the third one past the baker's. The roof beam came down on my mother. Her name was Anna. ANNA VARGA."),
				_l("wolfram", "...Leon?"),
				_n("The black Kaiserstuhl lowers its gun. A hand comes up to the mask, and the mask comes off."),
				_l("konrad", "They told me the house was empty. I read your name on the list. I read it four hundred and twelve times. And I have been training my corps to kill you. Oh, my boy."),
				_l("leon", "Why. Just tell me WHY."),
				_l("konrad", "Because Grau cannot be reached by an army. Only by a man he trusts. I let Varnhalt burn so he would trust me. I have carried one bullet for fifteen years, and I have been waiting to stand close enough to use it."),
				_l("konrad", "Black Claw! All units! The standard turns. Our enemy is in that fortress, and he always was. With the grey Sturmjäger: FORWARD!"),
				_l("grau", "Varga. So. Fifteen years, and you open your hand at the last gate. Garde. Kill them all. The traitor first."),
			], "effects": [
				{"spawn": StoryMaps.throne_gate_reinforcements()},
				{"convert": {"group": "claw"}},
				{"rename": {"pilot": "wolfram", "to": "konrad", "callsign": "KONRAD (Kaiserstuhl)"}},
				{"plot_armor": {"pilot": "konrad", "value": 1}},   # he has to be standing at the gate when it falls
			]},
			{"on": "turn", "turn": 3, "unless_fired": "reveal", "id": "reveal", "lines": [
				_l("leon", "Wolfram! Open channel. All of you can hear this. I don't care."),
				_l("leon", "The village was called Varnhalt. The house was the third one past the baker's. The roof beam came down on my mother. Her name was Anna. ANNA VARGA. I was seven, and I saw your walker on the ridge."),
				_l("wolfram", "...Leon?"),
				_n("The black Kaiserstuhl lowers its gun. A hand comes up to the mask, and the mask comes off."),
				_l("konrad", "They told me the house was empty. I read your name on the list. I read it four hundred and twelve times. And I have been training my corps to kill you. Oh, my boy."),
				_l("leon", "Why. Just tell me WHY."),
				_l("konrad", "Because Grau cannot be reached by an army. Only by a man he trusts. I let Varnhalt burn so he would trust me. I have carried one bullet for fifteen years, and I have been waiting to stand close enough to use it."),
				_l("konrad", "Black Claw! All units! The standard turns. Our enemy is in that fortress, and he always was. With the grey Sturmjäger: FORWARD!"),
				_l("grau", "Varga. So. Fifteen years, and you open your hand at the last gate. Garde. Kill them all. The traitor first."),
			], "effects": [
				{"spawn": StoryMaps.throne_gate_reinforcements()},
				{"convert": {"group": "claw"}},
				{"rename": {"pilot": "wolfram", "to": "konrad", "callsign": "KONRAD (Kaiserstuhl)"}},
				{"plot_armor": {"pilot": "konrad", "value": 1}},   # he has to be standing at the gate when it falls
			]},
			{"on": "turn", "turn": 1, "if_fired": "reveal", "lines": [
				_l("chad", "Wait, wait, wait. Scary mask guy is LEON'S DAD? And he's on OUR side? And he was on our side the WHOLE TIME?"),
				_l("mira", "He let a village burn to get a seat at a table, Brewster. Don't call that 'our side'. ...Leon. I'm here. Left flank. Like always."),
				_l("brann", "Varga! You and I will have WORDS about that boy when this is done. Until then, your walkers follow mine. GARDE AHEAD! EIGHTH IRON, BLACK CLAW: TAKE THAT GATE!"),
			]},
		],
		"post": [
			_n("The Throne Gate, in Coalition and Black Claw hands. Two walkers stand side by side for the first time: one grey, one black."),
			_l("konrad", "You have her way of standing. I should have seen it at the pass. I think I did see it. I couldn't take the shot and I didn't know why."),
			_l("leon", "You let her die."),
			_l("konrad", "Yes."),
			_l("leon", "You let four hundred people die, and you let me think you were one of them, and then you stood on a ridge and WATCHED."),
			_l("konrad", "Yes. I weighed a village against a war, Leon, and I chose. I have never once asked anyone to forgive it. I am not asking you. I am asking you for one more hour. He's in there. Let me finish what it cost."),
			_l("leon", "...One hour. Then you and I are going to talk. For a long time."),
			_l("konrad", "I would like that more than I can tell you."),
			_l("grau", "Touching. The traitor and his whelp. Come in, then, both of you. I had this walker built for exactly one purpose, and I have waited years to see whether it works."),
		],
	})

	list.append({
		"id": "m12", "kind": "mission", "act": ACT_3, "title": "IRON GHOST",
		"synopsis": "The Marshal, the Ragnarök, and one last debt.",
		"map": maps["m12"], "bg": "throne_gate", "post_bg": "parade_court",
		"lose_if_lost": ["leon"], "win_if_down": "grau",
		"win_text": "The Ragnarök is down. Supreme Marshal Grau is dead, and the war is over.",
		"pre": [
			_l("grau", "Fifteen years I kept you at my right hand, Varga. I knew what you were by the second. I kept you because you were USEFUL. Your corps won me half a continent."),
			_l("konrad", "And I let you have it, Marshal, one victory at a time, so that you would one day walk out of that bunker and stand where I could see you. Thank you for coming outside."),
			_l("grau", "The Ragnarök does not need a bunker. It IS one."),
			_l("brann", "That is the ugliest walker I have ever seen and I want one. EIGHTH IRON! That thing out-guns every one of us. So we don't duel it. We break his Garde, we get around it, and we hit it from every side at once!"),
			_l("ilse", "I have the range, my Sturmjäger. Say the word."),
			_l("mira", "Left flank. Like always. Don't make me say the rest."),
			_l("chad", "BIG RIG! For the record: best war I ever volunteered for."),
			_l("leon", "...Father. Stay beside me."),
			_l("konrad", "To the end, Leon."),
		],
		"triggers": [
			{"on": "skirmish", "pilot": "grau", "vs": "leon", "id": "sacrifice", "lines": [
				_l("grau", "The whelp first. Let the father watch, for once, from close by."),
				_n("The Ragnarök's siege barrels come down level with the grey Sturmjäger's cockpit. There is no time to move. A black shape crosses the court faster than a command walker should be able to."),
				_l("konrad", "NOT THIS TIME!"),
				_n("The shell takes the black Kaiserstuhl through the chest plate. It does not fall. It walks forward into the Ragnarök's guns and fires once, point blank, the shot it has been saving for fifteen years."),
				_l("grau", "My armour... he's breached my ARMOUR!"),
				_l("leon", "FATHER!"),
				_l("konrad", "I'm here. I'm still... Leon. Listen. I stood on a ridge once and did nothing. I wanted you to see me move."),
				_l("konrad", "I let our family die to end this war. That was my choice and I'll answer for it where I'm going. But you... you were never part of the price. You were the one thing I got wrong in my own favour."),
				_l("leon", "Don't. Don't you DARE. You said one hour, you said we'd TALK..."),
				_l("konrad", "We are talking. ...You have her way of standing. Did I tell you that? Finish it, son. He's open. Go."),
				_n("The black Kaiserstuhl's lens goes dark."),
				_l("leon", "...Squad. All walkers. He's breached. BRING IT DOWN."),
			], "effects": [
				{"cancel_skirmish": true},
				{"destroy": {"pilot": "konrad"}},
				{"plot_armor": {"pilot": "grau", "value": 0}},   # until now the Ragnarök could not be brought down
				{"damage": {"pilot": "grau", "amount": 75}},
				{"plot_armor": {"pilot": "leon", "value": 1}},   # what Konrad bought: Leon's second wind, again
			]},
			{"on": "turn", "turn": 3, "unless_fired": "sacrifice", "id": "sacrifice", "lines": [
				_l("grau", "Enough of this. The whelp first. Let the father watch, for once, from close by."),
				_n("The Ragnarök's siege barrels swing across the court and settle on the grey Sturmjäger's cockpit. There is no time to move. A black shape crosses the court faster than a command walker should be able to."),
				_l("konrad", "NOT THIS TIME!"),
				_n("The shell takes the black Kaiserstuhl through the chest plate. It does not fall. It walks forward into the Ragnarök's guns and fires once, point blank, the shot it has been saving for fifteen years."),
				_l("grau", "My armour... he's breached my ARMOUR!"),
				_l("leon", "FATHER!"),
				_l("konrad", "I'm here. I'm still... Leon. Listen. I stood on a ridge once and did nothing. I wanted you to see me move."),
				_l("konrad", "I let our family die to end this war. That was my choice and I'll answer for it where I'm going. But you... you were never part of the price. You were the one thing I got wrong in my own favour."),
				_l("leon", "Don't. Don't you DARE. You said one hour, you said we'd TALK..."),
				_l("konrad", "We are talking. ...You have her way of standing. Did I tell you that? Finish it, son. He's open. Go."),
				_n("The black Kaiserstuhl's lens goes dark."),
				_l("leon", "...Squad. All walkers. He's breached. BRING IT DOWN."),
			], "effects": [
				{"destroy": {"pilot": "konrad"}},
				{"plot_armor": {"pilot": "grau", "value": 0}},   # until now the Ragnarök could not be brought down
				{"damage": {"pilot": "grau", "amount": 75}},
				{"plot_armor": {"pilot": "leon", "value": 1}},   # what Konrad bought: Leon's second wind, again
			]},
			{"on": "hull", "pilot": "grau", "below": 35, "lines": [
				_l("grau", "Impossible. This machine cost more than your entire Division! I am the SYNDIKAT! Without me there is nothing!"),
				_l("leon", "There was a village. It had a baker. That was something."),
			]},
		],
		"post": [
			_n("The Ragnarök burns on the parade court. It takes a long time."),
			_l("brann", "It's done. Signals, send it in clear, every band: Grau is dead. The Syndikat's standard is down. The war is over."),
			_n("Leon climbs up onto the wreck of the black Kaiserstuhl and gets the hatch open."),
			_l("leon", "...He's gone. There's a photograph taped to the gunsight. It's the three of us. It's been there so long the tape's gone yellow."),
			_l("mira", "Leon... I'm here. You don't have to say anything. Just... I'm here."),
			_l("chad", "Hey. For what it's worth, buddy. He moved. At the end. He moved."),
			_l("ilse", "Commander Wolfram never once missed. Not in fifteen years. He was saving it. ...I think I understand saving something for one person."),
			_l("leon", "He asked me not to forgive him. I don't. I don't think I ever will. But I'm going to put his name where it belongs."),
			_l("brann", "Then we'll go together, lad. All of us."),
		],
	})

	# ====================================================================== EPILOGUE
	list.append({
		"id": "epilogue", "kind": "scene", "act": "EPILOGUE", "title": "THE STONE AT VARNHALT",
		"synopsis": "A rebuilt village, and one more name.",
		"bg": "memorial",
		"lines": [
			_n("One year later. Varnhalt. There is a bakery again, third house from the square."),
			_n("The memorial stone carries four hundred and twelve names. Two of them have been wrong for sixteen years."),
			_l("brann", "They let me carry the chisel. I said I'd do it with my bare hands and the mayor asked me, very politely, not to."),
			_l("chad", "So, uh. Big Rig Haulage and Demolition is open for business. First job's free. It's this. I brought the scaffolding."),
			_l("mira", "You're both ridiculous. ...Leon. Are you ready? You don't have to be. We'll wait. I'll wait. I-it's not a big deal, I'm just good at waiting!"),
			_l("leon", "I'm ready."),
			_n("He strikes one name off the stone: LEON VARGA, aged seven. He is, after all, standing right here."),
			_n("And under ANNA VARGA he cuts a new line, slowly, and gets it straight."),
			_n("KONRAD VARGA. HE CAME BACK."),
			_l("leon", "...Hammerfeld's a good name. Sturdy. I think I'll keep it, if that's all right."),
			_l("brann", "HA! ...Yes, lad. That's all right."),
			_l("mira", "Come on. There's bread. I already bought you some. Don't read into it."),
			_l("leon", "Thank you, Mira."),
			_n("OPERATION: IRON GRID // CAMPAIGN COMPLETE"),
		],
	})
	return list
