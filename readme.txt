				Bardcraft
				By therealralts

Version: 1.0.0

=========
Contents
=========
1.	Requirements
2.	Description
3.	Permissions
4.	Installation
5.	Removal
6.	Incompatibilities
7.	Credits

=============
Requirements
=============
Morrowind
OpenMW 0.49

============
Description
============
Adds a MIDI-based musical performance system, with custom songwriting, group performance, and skill progression mechanics.

============
Permissions
============
Modify my mod, but credit me as the original creator

=========
Overview
=========
Bardcraft is a fully-featured bard experience for Morrowind, powered by OpenMW-Lua. Perform music, level up your skills, compose your own songs, and gather a troupe of unique performers as you make a living playing taverns and streets across Vvardenfell.

-------------
Key Features
-------------
Bardcraft: A new character skill that lies at the heart of the mod's gameplay loop. At level 1, you'll struggle through basic scales, and likely be thrown out (or assaulted) in any tavern you dare to test your mettle in. Keep at it. The more you play, the better you'll become.

Dynamic reactions: Great performances will earn you tips in real-time, and the crowd might even erupt into cheers. Truly awful performances, on the other hand, will get you pelted with food and drinks by rowdy taverngoers, or even get you banned from a venue for a while. The mod has plenty of variety -- over 700 unique tip messages, patron and publican comments, depending on a mixture of performance quality, complexity, and NPC race.

Song learning: Booksellers stock a few basic songbooks that'll teach simple songs to get you started. But any good bard is also an adventurer, and things are no different in Morrowind. Hundreds of potential music box locations have been hand-placed in dungeons across Vvardenfell, with a unique selection appearing in each playthrough. The more difficult the dungeon, the higher tier the music box. When activated, they'll play a rendition of a random song of their respective tier, teaching it to you and allowing you to play it yourself. They can be picked up, and make great home decorations :)

Assemble a troupe: You can perform solo, but it's more fun with a band! Bards-for-hire can be found throughout the taverns of Vvardenfell. For a price, they'll lend their talents and travel with you. Each performer has a distinct personality, backstory, instrument, and fee.

Instrument sheathing: Most instruments can be worn on your back by dragging them onto your character as you would a piece of armor.

MIDI-based performances: All of the mod's songs are pure MIDI, played in real time, note-by-note. This enables instrument animations that are truly synced to the notes being played, and audible flubs with low performer skill.

Custom songwriting: Buy blank sheet music from a bookseller and write songs in-game, completely freeform, using a MIDI piano roll-style interface. The editor is simple but functional. You can choose instruments, parts, adjust BPM and time signature, toggle looping, and use helpful tools like scale highlighting and snapping. More functionality, like copy/paste, undo/redo, and group selection is planned for the near future.

MIDI importing: Any MIDI file can be imported, and it'll just work. Place the file into the folder "midi/Bardcraft/custom"; upon loading in, the song will be added to your songwriting drafts. From there, you can make any tweaks you'd like, and then finalize it using blank sheet music, as you would any other song.

------------
Instruments
------------
Currently, there are five playable instruments.

The vanilla lute and drum are playable, and have had their prices adjusted to be more reasonable. All Tamriel Data lutes/drums are supported by default.
Ocarinas, bass flutes, and fiddles are new additions.
All vanilla general merchants will stock a random variety of instruments. Fiddles, being an uncommon Cyrodiilic import, can only be purchased in Pelagiad.

----------------------
Where to Buy Supplies
----------------------
- INSTRUMENTS:
	- Ald'ruhn: Malpenix Blonia (Redoran Council Hall)
	- Ald'ruhn: Tiras Sadus
	- Ald Velothi: Sedam Omalen (Outpost)
	- Balmora: Clagius Clanler
	- Balmora: Ra'Virr
	- Caldera: Verick Gemain
	- Dagon Fel: Heifnir
	- Ghostgate: Fonas Retheran (Tower of Dusk)
	- Khuul: Thongar
	- Molag Mar: Vasesius Viciulus (Waistworks)
	- Pelagiad: Mebestian Ence
	- Seyda Neen: Arrille
	- Suran: Ashumanu Eraishah (Suran Tradehouse)
	- Suran: Ralds Oril
	- Tel Aruhn: Ferele Athram
	- Tel Branora: Fadase Selvayn
	- Tel Mora: Berwen
	- Vivec, Foreign Quarter: Jeanne (Canalworks)
	- Vivec, Hlaalu: Gadayn Andarys (Plaza)
	- Vivec, Redoran: Balen Andrano (Waistworks)
	- Vivec, St. Delyn: Lucretinaus Olcinius (Plaza)
	- Vivec, St. Delyn: Mevel Fererus (Plaza)
	- Vivec, St. Delyn: Tervur Braven (Plaza)

- All vanilla booksellers will carry some blank sheet music and songbooks (restocking every few months).
- Arrille in Seyda Neen will always carry a lute and a restocking beginner songbook.

------------------
Recruitable Bards
------------------
- LUTE:
	- Strumak gro-Bol (Madach Tradehouse, Gnisis)
		Hire cost: 300G
		An unusually introspective Orc who found solace in the lute after a "disagreement" with his stronghold. Speaks little, but his music is very expressive. Might occasionally grumble about how "true strength is found in accepting sorrow."
	- Camilla of Cheydinhal (Halfway Tavern, Pelagiad)
		Hire cost: 1500G
		A former Imperial court performer now scraping by in Morrowind after a run of bad luck. Constantly name-drops nobility no one here has heard of. Possesses considerable talent, but undersells herself.

- OCARINA:
	- Sees-Silent-Reeds (Arrille's Tradehouse, Seyda Neen)
		Hire cost: 100G
		A calm and patient Argonian who offers cryptic but gentle advice. Claims to have learned all they know from watching the waves on the shores of the Bitter Coast. Fascinated by the player's journey as an outlander.
	- Elara Endre (Mages Guild, Ald'ruhn)
		Hire cost: 300G
		A Breton Mages Guild initiate who finds mathematical beauty in musical scales and modes. Plays her ocarina with precise, almost clinical skill, using it to "explore tonal relationships." Offers to join because she sees the player's band as a "fascinating practical application of harmonic theory." Slightly socially awkward.

- FLUTE:
	- Sargon Assinabi (Varo Tradehouse, Vos)
		Hire cost: 200G
		A recently exiled Ashlander who left his tribe with his flute as one of his few possessions, and has decided to try to find a place in settled culture. Attempting to build a life as a wandering musician, but finding settled folk have little appreciation for solo flutists.

- DRUM:
	- Ra'jira "Quick-Paws" (Black Shalk Cornerclub, Vivec, Foreign Quarter)
		Hire cost: 300G
		An incredibly energetic Khajiit whose drumming is fast, complex, and infectious. Offers to join for the thrill of new rhythms and the promise of "much coin for lively beats, yes?"
	- Rels Llervu (Andus Tradehouse, Maar Gan)
		Hire cost: 1000G
		A stern House Redoran drummer who makes yearly journeys up to the Urshilaku tribe to study their traditional drumming technique. Holds no love for the Ashlanders, but views it as a preserved form of ancient Dunmer percussive tradition, and recognizes its potent martial impact.

- FIDDLE:
	- Lucian Caro (Six Fishes, Ebonheart)
		Hire cost: 1500G
		A classically-trained fiddler (or "vielle" player, as he prefers) of the Imperial Conservatory, stuck in Morrowind on what he calls an "extended sabbatical". Very skilled and highly confident, though not to the point of blatant arrogance. Knows what he's worth, and keeps things strictly professional.

=============
Installation
=============
1. Place the contents of the archive into your Data Files folder, or add it as a data directory in the OpenMW launcher.
2. Enable "Bardcraft.omwscripts" and "Bardcraft.ESP" in your load order.
3. In your OpenMW launcher, go to Settings > Visuals > Animations and make sure "Use Additional Animation Sources" is checked. "Smooth Animation Transitions" is also highly recommended but not required.
4. (optional, but recommended): Keyboard navigation can cause issues and annoying behavior with this mod's UI if you accidentally press Tab. Unless you actively use it, I recommend disabling it. In your settings.cfg, add the [GUI] section if it doesn't exist, and in that section, add: keyboard navigation = false

========
Removal
========
Remove the mod's files from your Data Files folder or unlink them in the OpenMW launcher.

==================
Incompatibilities
==================
ReAnimation: Make sure to use the latest (4/7/2025+) version of that mod. Older versions will throw an error and stop this mod's animations from playing.

========
Credits
========
Thanks to Bethesda Softworks for developing Morrowind and the Construction Set.
Thanks to Brucoms for developing the TES3 Readme Generator this readme was made from.
Attributions for all used assets are provided in credits.txt.
