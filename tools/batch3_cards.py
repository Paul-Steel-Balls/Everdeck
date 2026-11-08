#!/usr/bin/env python3
"""Batch 3: Reginald (50 new) + Larry (48 new) = 98 cards. Total -> 340.
All cards hand-designed against Phase 1 rules (scaled premium, bans,
spell feasibility, Legendary distinctness). Art id = card id (unique)."""
import json

R = []  # Reginald
L = []  # Larry


def minion(lst, cid, name, cost, a, h, rarity, text, flavor, keywords=(),
          effect="", value=0, target="none", dr="", dr_value=0,
          dr_target="none", note=None):
    c = {"id": cid, "name": name, "class": "reginald" if lst is R else "larry",
         "cost": cost, "type": "minion", "attack": a, "health": h,
         "keywords": list(keywords), "effect": effect, "effect_value": value,
         "target": target, "rarity": rarity, "text": text, "flavor": flavor,
         "art": cid, "deathrattle": dr, "deathrattle_value": dr_value,
         "deathrattle_target": dr_target}
    if note:
        c["design_note"] = note
    lst.append(c)


def spell(lst, cid, name, cost, rarity, text, flavor, effect, value=0,
          target="none", note=None):
    c = {"id": cid, "name": name, "class": "reginald" if lst is R else "larry",
         "cost": cost, "type": "spell", "attack": 0, "health": 0,
         "keywords": [], "effect": effect, "effect_value": value,
         "target": target, "rarity": rarity, "text": text, "flavor": flavor,
         "art": cid, "deathrattle": "", "deathrattle_value": 0,
         "deathrattle_target": "none"}
    if note:
        c["design_note"] = note
    lst.append(c)


# ================= REGINALD (50) =================
# Cost 1 (4): target 4. C3 E1.
minion(R, "reg_squire_tim", "Squire Tim", 1, 2, 2, "Common", "",
       "Tim is extremely normal. He filed his squire paperwork early.")
minion(R, "reg_shield_squire", "Shield Squire", 1, 1, 2, "Common", "Taunt.",
       "His shield is bigger than he is. That is the point.", keywords=["taunt"])
spell(R, "reg_blessing", "Blessing of the Order", 1, "Epic",
      "Give a friendly minion +1/+1.",
      "Form 12-B: Application for Blessing. Approved.",
      "buff_friendly", 1, "friendly_minion")
spell(R, "reg_precise_strike", "Precise Strike", 1, "Common",
      "Deal 2 damage to an enemy minion.",
      "One thrust. Exactly where the form said to put it.",
      "damage", 2, "enemy_minion")
# Cost 2 (8): target 5. C6 R1 E1.
minion(R, "reg_footman", "Footman", 2, 3, 2, "Common", "",
       "Marches in straight lines. Proudly.")
minion(R, "reg_pikeman", "Pikeman", 2, 2, 3, "Common", "",
       "The pike is regulation length. The pikeman is regulation height.")
minion(R, "reg_castle_guard", "Castle Guard", 2, 2, 2, "Common", "Taunt.",
       "Has guarded this exact doorway for eleven years.", keywords=["taunt"])
minion(R, "reg_lance_squire", "Lance Squire", 2, 2, 2, "Common", "Charge.",
       "Practicing for the day he gets a real lance.", keywords=["charge"])
minion(R, "reg_chirurgeon", "Chirurgeon", 2, 2, 2, "Common",
       "Battlecry: Restore 3 Health to your hero.",
       "Bandages filed under B. Blood filed under B for 'bad'.",
       effect="heal_hero", value=3)
minion(R, "reg_crossbow", "Crossbow Squire", 2, 1, 3, "Epic",
       "Battlecry: Deal 1 damage to an enemy minion.",
       "One bolt. One form. One very surprised enemy.",
       effect="damage", value=1, target="enemy_minion")
spell(R, "reg_greater_blessing", "Greater Blessing", 2, "Rare",
      "Give a friendly minion +2/+2.",
      "Form 12-C: Application for a BIGGER Blessing. Also approved.",
      "buff_friendly", 2, "friendly_minion")
spell(R, "reg_duel", "Duel", 2, "Common",
      "Deal 3 damage to an enemy minion.",
      "Pistols at dawn. Paperwork at noon.", "damage", 3, "enemy_minion")
# Cost 3 (10): target 7. C4 R4 E1 L1.
minion(R, "reg_shield_knight", "Shield Knight", 3, 3, 3, "Common", "Taunt.",
       "The shield has its own squire.", keywords=["taunt"])
minion(R, "reg_lance_knight", "Lance Knight", 3, 3, 3, "Common", "Charge.",
       "CHARGE! ...Sorry. I got excited. It happens.", keywords=["charge"])
minion(R, "reg_sergeant", "Sergeant", 3, 3, 2, "Common",
       "Battlecry: Give another friendly minion +1/+1.",
       "Drop and give me twenty. Then file the report.",
       effect="buff_friendly", value=1, target="friendly_minion")
minion(R, "reg_hospitaller", "Hospitaller", 3, 3, 3, "Common",
       "Battlecry: Restore 3 Health to your hero.",
       "Soup, bandages, and a lecture on hydration.",
       effect="heal_hero", value=3)
minion(R, "reg_vengeful", "Vengeful Knight", 3, 3, 3, "Rare",
       "Deathrattle: Deal 1 damage to a random enemy minion.",
       "He filed his vengeance in triplicate.", dr="damage", dr_value=1,
       dr_target="enemy_minion")
minion(R, "reg_war_horn", "War Horn", 3, 3, 3, "Rare",
       "Battlecry: Gain 1 mana this turn.",
       "One blast means charge. Two blasts means paperwork.",
       effect="gain_mana", value=1)
minion(R, "reg_sanctuary", "Sanctuary Knight", 3, 2, 3, "Rare",
       "Taunt. Battlecry: Restore 3 Health to your hero.",
       "You shall not pass. Also, have some soup.",
       keywords=["taunt"], effect="heal_hero", value=3)
minion(R, "reg_banner_order", "Banner of the Order", 3, 1, 2, "Epic",
       "Battlecry: Give another friendly minion +1/+1. "
       "Deathrattle: Give a friendly minion +1/+1.",
       "The banner inspires. Even after the bearer stops.",
       effect="buff_friendly", value=1, target="friendly_minion",
       dr="buff_friendly", dr_value=1, dr_target="friendly_minion")
minion(R, "reg_oathbound", "Aldric the Oathbound", 3, 2, 2, "Legendary",
       "Battlecry: Give another friendly minion +1/+1. "
       "Deathrattle: Deal 1 damage to a random enemy minion.",
       "Swore an oath. Kept it. Twice.",
       effect="buff_friendly", value=1, target="friendly_minion",
       dr="damage", dr_value=1, dr_target="enemy_minion")
spell(R, "reg_smite", "Smite", 3, "Rare",
      "Deal 5 damage to an enemy minion.",
      "Judgment is swift. The paperwork is swifter.",
      "damage", 5, "enemy_minion")
# Cost 4 (12): target 9. C4 R4 E3 L1.
minion(R, "reg_tower_knight", "Tower Knight", 4, 4, 4, "Common", "Taunt.",
       "Built like a tower. Acts like one too.", keywords=["taunt"])
minion(R, "reg_charging_knight", "Charging Knight", 4, 4, 4, "Common",
       "Charge.", "His horse is named Steve. Steve is fast.",
       keywords=["charge"])
minion(R, "reg_captain", "Knight-Captain", 4, 4, 3, "Common",
       "Battlecry: Give another friendly minion +1/+1.",
       "Promotes people. Demotes paperwork.",
       effect="buff_friendly", value=1, target="friendly_minion")
minion(R, "reg_grand_hospitaller", "Grand Hospitaller", 4, 3, 4, "Common",
       "Battlecry: Restore 5 Health to your hero.",
       "Now with extra soup. And a clipboard.",
       effect="heal_hero", value=5)
minion(R, "reg_high_marshal", "High Marshal", 4, 2, 3, "Rare",
       "Battlecry: Give another friendly minion +2/+2.",
       "His orders are final. His forms are finaler.",
       effect="buff_friendly", value=2, target="friendly_minion")
minion(R, "reg_fallen_standard", "Fallen Standard", 4, 4, 3, "Rare",
       "Deathrattle: Give a friendly minion +1/+1.",
       "The standard falls. The inspiration does not.",
       dr="buff_friendly", dr_value=1, dr_target="friendly_minion")
minion(R, "reg_mercy", "Knight of Mercy", 4, 3, 4, "Rare",
       "Deathrattle: Restore 5 Health to your hero.",
       "Mercy arrives late. It still arrives.",
       dr="heal_hero", dr_value=5)
minion(R, "reg_twinblade", "Twin-Blade Knight", 4, 4, 3, "Epic",
       "Battlecry: Deal 1 damage to an enemy minion. "
       "Deathrattle: Deal 1 damage to a random enemy minion.",
       "Two blades. Two forms. Zero mercy.",
       effect="damage", value=1, target="enemy_minion",
       dr="damage", dr_value=1, dr_target="enemy_minion")
minion(R, "reg_war_banner", "War Banner", 4, 2, 3, "Epic",
       "Battlecry: Give another friendly minion +1/+1. "
       "Deathrattle: Give a friendly minion +1/+1.",
       "Wave it. Then wave the paperwork.",
       effect="buff_friendly", value=1, target="friendly_minion",
       dr="buff_friendly", dr_value=1, dr_target="friendly_minion")
minion(R, "reg_judgment", "Knight of Judgment", 4, 4, 3, "Epic",
       "Battlecry: Deal 2 damage to an enemy minion.",
       "The verdict is in. It is not good.",
       effect="damage", value=2, target="enemy_minion")
minion(R, "reg_prudence", "Dame Prudence, the Unflappable", 4, 3, 2,
       "Legendary", "Battlecry: Give all friendly minions +1/+1.",
       "Nothing rattles her. She has seen the forms.",
       effect="buff_all_friendly", value=1)
spell(R, "reg_summary_execution", "Summary Execution", 4, "Rare",
      "Destroy an enemy minion.",
      "The trial was brief. The sentence was briefer.",
      "destroy", 0, "enemy_minion")
# Cost 5 (8): target 10. C2 R3 E2 L1.
minion(R, "reg_grand_bulwark", "Grand Bulwark", 5, 5, 4, "Common", "Taunt.",
       "A wall with a knighthood.", keywords=["taunt"])
minion(R, "reg_grand_charger", "Grand Charger", 5, 5, 4, "Common", "Charge.",
       "Steve's bigger cousin. Also named Steve.",
       keywords=["charge"])
minion(R, "reg_lord_marshal", "Lord Marshal", 5, 3, 3, "Rare",
       "Battlecry: Give another friendly minion +2/+2.",
       "Outranks everyone. Out-forms everyone.",
       effect="buff_friendly", value=2, target="friendly_minion")
minion(R, "reg_verdict", "Knight of the Verdict", 5, 4, 3, "Rare",
       "Battlecry: Deal 3 damage to an enemy minion.",
       "Guilty. Next case.", effect="damage", value=3, target="enemy_minion")
minion(R, "reg_fallen_lord", "Fallen Lord", 5, 3, 3, "Rare",
       "Deathrattle: Give a friendly minion +2/+2.",
       "Falls in battle. Rises in the paperwork.",
       dr="buff_friendly", dr_value=2, dr_target="friendly_minion")
minion(R, "reg_commander", "Knight-Commander", 5, 5, 3, "Epic",
       "Battlecry: Give another friendly minion +1/+1.",
       "Commands knights. Commands respect. Commands forms.",
       effect="buff_friendly", value=1, target="friendly_minion")
minion(R, "reg_eternal_banner", "Eternal Banner", 5, 3, 3, "Epic",
       "Battlecry: Give another friendly minion +1/+1. "
       "Deathrattle: Give a friendly minion +1/+1.",
       "It has never been lowered. It has been filed.",
       effect="buff_friendly", value=1, target="friendly_minion",
       dr="buff_friendly", dr_value=1, dr_target="friendly_minion")
minion(R, "reg_godwin", "Sir Godwin, the Merciful", 5, 4, 3, "Legendary",
       "Battlecry: Deal 2 damage to an enemy minion. "
       "Deathrattle: Restore 3 Health to your hero.",
       "Mercy first. Judgment second. Forms third.",
       effect="damage", value=2, target="enemy_minion",
       dr="heal_hero", dr_value=3)
# Cost 6 (5): target 11. C1 R2 E1 L1.
minion(R, "reg_bastion", "Bastion Knight", 6, 5, 5, "Common", "Taunt.",
       "The castle moved. It is him.", keywords=["taunt"])
minion(R, "reg_grand_marshal", "Grand Marshal", 6, 4, 3, "Rare",
       "Battlecry: Give another friendly minion +2/+2.",
       "His signature is worth more than your army.",
       effect="buff_friendly", value=2, target="friendly_minion")
minion(R, "reg_final_word", "Knight of the Final Word", 6, 5, 3, "Rare",
       "Battlecry: Deal 3 damage to an enemy minion.",
       "And that is final.", effect="damage", value=3, target="enemy_minion")
minion(R, "reg_reliquary", "Reliquary Banner", 6, 3, 4, "Epic",
       "Battlecry: Give another friendly minion +1/+1. "
       "Deathrattle: Give a friendly minion +1/+1.",
       "It holds a relic. The relic holds a grudge.",
       effect="buff_friendly", value=1, target="friendly_minion",
       dr="buff_friendly", dr_value=1, dr_target="friendly_minion")
minion(R, "reg_barrington", "Lord Barrington, the Steadfast", 6, 4, 3,
       "Legendary", "Deathrattle: Give all friendly minions +1/+1.",
       "Even death files the right forms.",
       dr="buff_all_friendly", dr_value=1)
# Cost 7 (3): target 14. E1 R1 L1.
minion(R, "reg_colossus", "Colossus of the Order", 7, 7, 6, "Epic", "Taunt.",
       "Seven feet tall. Nine feet of paperwork.",
       keywords=["taunt"])
minion(R, "reg_champion", "Regent's Champion", 7, 5, 5, "Rare",
       "Battlecry: Give another friendly minion +2/+2.",
       "Fights for the Regent. Files for himself.",
       effect="buff_friendly", value=2, target="friendly_minion")
minion(R, "reg_everbloom", "Dame Everbloom", 7, 4, 4, "Legendary",
       "Battlecry: Restore 5 Health to your hero. "
       "Deathrattle: Give a friendly minion +2/+2.",
       "Carries the Eternal Standard. And snacks.",
       effect="heal_hero", value=5, dr="buff_friendly", dr_value=2,
       dr_target="friendly_minion")

# ================= LARRY (48) =================
# Cost 1 (6): target 4. C5 R1.
minion(L, "lar_dice_boy", "Dice Boy", 1, 2, 2, "Common", "",
       "Rolls dice. Loses dice. Finds dice.")
minion(L, "lar_chip", "Chip", 1, 2, 1, "Common", "Charge.",
       "Small chip. Big attitude.", keywords=["charge"])
minion(L, "lar_loaded_die", "Loaded Die", 1, 1, 2, "Common",
       "Battlecry: Deal 1 damage to a random enemy.",
       "Definitely not loaded. Definitely.",
       effect="random_enemy_damage", value=1)
spell(L, "lar_lucky_shot", "Lucky Shot", 1, "Rare",
      "Deal 2 damage to an enemy.",
      "Aimed at the wall. Hit the guy. Lucky.",
      "damage", 2, "any_enemy")
spell(L, "lar_wild_card", "Wild Card", 1, "Epic",
      "Deal 2 damage to a random enemy.",
      "Could hit anyone. Probably will.",
      "random_enemy_damage", 2)
spell(L, "lar_double_down", "Double Down", 1, "Rare",
      "Deal 1 damage to an enemy.",
      "If at first you don't succeed, bet twice as much.",
      "damage", 1, "any_enemy")
# Cost 2 (9): target 5. C5 R2 E1 L1.
minion(L, "lar_card_shark", "Card Shark", 2, 3, 2, "Common", "",
       "Not an actual shark. The cards are also not actual cards.")
minion(L, "lar_roulette", "Roulette Runner", 2, 2, 2, "Common",
       "Battlecry: Deal 1 damage to a random enemy.",
       "Runs the wheel. The wheel runs him.",
       effect="random_enemy_damage", value=1)
minion(L, "lar_slot", "Slot Machine", 2, 2, 2, "Common",
       "Deathrattle: Deal 1 damage to a random enemy.",
       "Three cherries. Zero survivors.",
       dr="random_enemy_damage", dr_value=1)
minion(L, "lar_ace", "Ace in the Hole", 2, 2, 2, "Rare",
       "Battlecry: Deal 1 damage to an enemy.",
       "It was up his sleeve the whole time.",
       effect="damage", value=1, target="any_enemy")
minion(L, "lar_pete", "Lucky Pete", 2, 2, 1, "Legendary",
       "Battlecry: Deal 1 damage to a random enemy. "
       "Deathrattle: Deal 1 damage to a random enemy minion.",
       "The coin loves him. Everyone else tolerates him.",
       effect="random_enemy_damage", value=1,
       dr="damage", dr_value=1, dr_target="enemy_minion")
spell(L, "lar_high_roller", "High Roller", 2, "Common",
      "Deal 3 damage to an enemy.",
      "Go big. Then go bigger.", "damage", 3, "any_enemy")
spell(L, "lar_roulette_wheel", "Roulette Wheel", 2, "Rare",
      "Deal 3 damage to a random enemy minion.",
      "Round and round it goes. Where it stops, someone regrets it.",
      "random_minion_damage", 3)
spell(L, "lar_ace_up", "Ace Up the Sleeve", 2, "Rare",
      "Deal 4 damage to a random enemy.",
      "There is always another ace.",
      "random_enemy_damage", 4)
spell(L, "lar_snake_eyes", "Snake Eyes", 2, "Epic",
      "Deal 1 damage to ALL enemy minions.",
      "Rolled snake eyes. Everyone loses.",
      "damage_all_enemy_minions", 1)
# Cost 3 (9): target 7. C5 R2 E1 L1.
minion(L, "lar_hustler", "Hustler", 3, 4, 3, "Common", "",
       "Hustles. Bumbles. Somehow wins.")
minion(L, "lar_jackpot", "Jackpot", 3, 3, 2, "Common",
       "Battlecry: Deal 2 damage to a random enemy.",
       "JACKPOT! (Some assembly required.)",
       effect="random_enemy_damage", value=2)
minion(L, "lar_craps", "Craps", 3, 3, 2, "Rare",
       "Deathrattle: Deal 2 damage to a random enemy.",
       "Crapped out. Everyone suffers.",
       dr="random_enemy_damage", dr_value=2)
minion(L, "lar_tessa", "Two-Face Tessa, the Card Sharp", 3, 3, 2,
       "Legendary", "Battlecry: Swap the Attack and Health of a random "
       "enemy minion.",
       "Two faces. Both cheating.", effect="swap_stats", value=0,
       target="enemy_minion")
minion(L, "lar_blackjack", "Blackjack", 3, 2, 3, "Epic",
       "Battlecry: Deal 1 damage to an enemy. "
       "Deathrattle: Deal 1 damage to a random enemy minion.",
       "Hit me. Then hit them.",
       effect="damage", value=1, target="any_enemy",
       dr="damage", dr_value=1, dr_target="enemy_minion")
minion(L, "lar_wheel", "Wheel of Misfortune", 3, 4, 2, "Common",
       "Battlecry: Deal 1 damage to a random enemy.",
       "Spin it. Regret it.", effect="random_enemy_damage", value=1)
minion(L, "lar_dice_golem", "Dice Golem", 3, 2, 3, "Rare",
       "Battlecry: Deal 2 damage to an enemy.",
       "Rolled a six. Then became the six.",
       effect="damage", value=2, target="any_enemy")
spell(L, "lar_big_bet", "Big Bet", 3, "Rare",
      "Deal 5 damage to an enemy.",
      "All in. No regrets. Some regrets.",
      "damage", 5, "any_enemy")
spell(L, "lar_rigged_deck", "Rigged Deck", 3, "Common",
      "Deal 2 damage to ALL minions.",
      "The deck was rigged. Against everyone.",
      "damage_all_minions", 2)
# Cost 4 (10): target 9. C5 R3 E1 L1.
minion(L, "lar_bettor", "High-Stakes Bettor", 4, 5, 3, "Common",
       "Battlecry: Deal 1 damage to a random enemy.",
       "Bets the house. IS the house.",
       effect="random_enemy_damage", value=1)
minion(L, "lar_dolores", "Dead-Eye Dolores", 4, 2, 2, "Legendary",
       "Battlecry: Deal 3 damage to an enemy. "
       "Deathrattle: Deal 2 damage to a random enemy.",
       "Never misses. Except when she does. Which is never.",
       effect="damage", value=3, target="any_enemy",
       dr="random_enemy_damage", dr_value=2)
minion(L, "lar_horse", "Dark Horse", 4, 4, 3, "Common",
       "Battlecry: Deal 2 damage to an enemy.",
       "Nobody bet on him. That was the mistake.",
       effect="damage", value=2, target="any_enemy")
minion(L, "lar_longshot", "Long Shot", 4, 4, 3, "Rare",
       "Deathrattle: Deal 2 damage to a random enemy.",
       "A million to one. Those are HIS odds.",
       dr="random_enemy_damage", dr_value=2)
minion(L, "lar_rigger", "Rigger", 4, 3, 3, "Epic",
       "Battlecry: Deal 2 damage to a random enemy. "
       "Deathrattle: Deal 1 damage to a random enemy minion.",
       "Rigs the game. Rigs the funeral too.",
       effect="random_enemy_damage", value=2,
       dr="damage", dr_value=1, dr_target="enemy_minion")
minion(L, "lar_monte", "Three-Card Monte", 4, 3, 4, "Rare",
       "Battlecry: Deal 1 damage to an enemy. "
       "Deathrattle: Deal 1 damage to a random enemy minion.",
       "Follow the card. Lose the game.",
       effect="damage", value=1, target="any_enemy",
       dr="damage", dr_value=1, dr_target="enemy_minion")
minion(L, "lar_bookie", "The Bookie", 4, 4, 4, "Rare",
       "Battlecry: Gain 1 mana this turn.",
       "Lends you mana. Collects later.",
       effect="gain_mana", value=1)
minion(L, "lar_shark_tank", "Shark Tank", 4, 4, 4, "Common",
       "Battlecry: Deal 1 damage to a random enemy.",
       "The sharks are also gambling.",
       effect="random_enemy_damage", value=1)
spell(L, "lar_kneecap", "Kneecap", 4, "Rare",
      "Destroy an enemy minion.",
      "The house collects its debts.",
      "destroy", 0, "enemy_minion")
spell(L, "lar_clear_table", "Clear the Table", 4, "Epic",
      "Deal 2 damage to ALL enemy minions.",
      "New game. New victims.", "damage_all_enemy_minions", 2)
# Cost 5 (8): target 10. C4 R1 E2 L1.
minion(L, "lar_whale", "The Whale", 5, 5, 4, "Common",
       "Battlecry: Deal 1 damage to a random enemy.",
       "Bets big. Loses bigger. Comes back anyway.",
       effect="random_enemy_damage", value=1)
minion(L, "lar_bessie", "Big Bessie, the Wheel", 5, 4, 4, "Legendary",
       "Deathrattle: Swap the Attack and Health of a random enemy minion.",
       "The wheel turns. So do your stats.",
       dr="swap_stats", dr_value=0, dr_target="enemy_minion")
minion(L, "lar_croupier", "Croupier", 5, 5, 3, "Common",
       "Battlecry: Deal 2 damage to an enemy.",
       "No more bets. Except this one.",
       effect="damage", value=2, target="any_enemy")
minion(L, "lar_fixer", "The Fixer", 5, 4, 4, "Rare",
       "Battlecry: Deal 1 damage to an enemy. "
       "Deathrattle: Deal 1 damage to a random enemy minion.",
       "Fixes games. Fixes people. Fixes everything.",
       effect="damage", value=1, target="any_enemy",
       dr="damage", dr_value=1, dr_target="enemy_minion")
minion(L, "lar_oddsmaker", "Oddsmaker", 5, 4, 3, "Epic",
       "Battlecry: Deal 2 damage to a random enemy. "
       "Deathrattle: Deal 1 damage to a random enemy minion.",
       "Sets the odds. Breaks the odds.",
       effect="random_enemy_damage", value=2,
       dr="damage", dr_value=1, dr_target="enemy_minion")
minion(L, "lar_lucky7", "Lucky Seven", 5, 5, 4, "Common",
       "Deathrattle: Deal 1 damage to a random enemy.",
       "Seven. Lucky. Until it isn't.",
       dr="random_enemy_damage", dr_value=1)
minion(L, "lar_pit_boss", "Pit Boss", 5, 6, 3, "Epic",
       "Battlecry: Deal 1 damage to an enemy.",
       "Runs the pit. Runs the game. Runs you.",
       effect="damage", value=1, target="any_enemy")
minion(L, "lar_cheat", "Cheat", 5, 3, 4, "Epic",
       "Battlecry: Deal 2 damage to a random enemy. "
       "Deathrattle: Deal 1 damage to a random enemy.",
       "Cheat. Win. Repeat.",
       effect="random_enemy_damage", value=2,
       dr="random_enemy_damage", dr_value=1)
# Cost 6 (4): target 11. C2 R1 E0 L1.
minion(L, "lar_madame", "Madame Misfortune", 6, 3, 3, "Legendary",
       "Battlecry: Deal 1 damage to ALL enemy minions. "
       "Deathrattle: Deal 2 damage to an enemy minion.",
       "Your fortune: everyone suffers. Including you.",
       effect="damage_all_enemy_minions", value=1,
       dr="damage", dr_value=2, dr_target="enemy_minion")
minion(L, "lar_whale_hunter", "Whale Hunter", 6, 5, 4, "Common",
       "Battlecry: Deal 2 damage to a random enemy.",
       "Hunts whales. The whales hunt back.",
       effect="random_enemy_damage", value=2)
minion(L, "lar_loaded_dice", "Loaded Dice", 6, 4, 4, "Rare",
       "Battlecry: Deal 2 damage to an enemy. "
       "Deathrattle: Deal 1 damage to a random enemy minion.",
       "Definitely not loaded. Definitely.",
       effect="damage", value=2, target="any_enemy",
       dr="damage", dr_value=1, dr_target="enemy_minion")
minion(L, "lar_big_one", "The Big Score", 6, 5, 5, "Common",
       "Battlecry: Deal 1 damage to a random enemy.",
       "The big score. Finally.", effect="random_enemy_damage", value=1)
# Cost 7 (2): target 14. C1 E1.
minion(L, "lar_magnate", "Casino Magnate", 7, 7, 5, "Common",
       "Battlecry: Deal 2 damage to an enemy.",
       "Owns the casino. Owns the game.",
       effect="damage", value=2, target="any_enemy")
minion(L, "lar_house", "The House Always Wins", 7, 6, 5, "Epic",
       "Battlecry: Deal 2 damage to a random enemy. "
       "Deathrattle: Deal 1 damage to a random enemy minion.",
       "The house always wins. Larry IS the house.",
       effect="random_enemy_damage", value=2,
       dr="damage", dr_value=1, dr_target="enemy_minion")

if __name__ == "__main__":
    from collections import Counter
    for lst, name, curve, rar in (
            (R, "reginald", {1: 4, 2: 8, 3: 10, 4: 12, 5: 8, 6: 5, 7: 3},
             {"Common": 20, "Rare": 15, "Epic": 10, "Legendary": 5}),
            (L, "larry", {1: 6, 2: 9, 3: 9, 4: 10, 5: 8, 6: 4, 7: 2},
             {"Common": 20, "Rare": 14, "Epic": 9, "Legendary": 5})):
        print(name, "count:", len(lst),
              "curve:", dict(sorted(Counter(c["cost"] for c in lst).items())),
              "rarity:", dict(Counter(c["rarity"] for c in lst)),
              "minions:", sum(1 for c in lst if c["type"] == "minion"),
              "spells:", sum(1 for c in lst if c["type"] == "spell"),
              "vanilla:", sum(1 for c in lst if c["type"] == "minion"
                              and not c["keywords"] and not c["effect"]
                              and not c["deathrattle"]))
        assert dict(sorted(Counter(c["cost"] for c in lst).items())) == curve
        assert dict(Counter(c["rarity"] for c in lst)) == rar
    # Budget self-check (minions only).
    VANILLA = {1: 4, 2: 5, 3: 6, 4: 8, 5: 9, 6: 10, 7: 12, 8: 13, 9: 14, 10: 16}

    def prem(cost):
        return 0 if cost <= 2 else (1 if cost <= 6 else 2)

    def pts(eff, val):
        if eff == "":
            return 0
        if eff == "damage":
            return val
        if eff == "damage_all_enemy_minions":
            return {1: 3, 2: 5}[val]
        if eff == "heal_hero":
            return {3: 1, 5: 2}[val]
        if eff == "draw":
            return {1: 2, 2: 3}[val]
        if eff == "summon_token":
            return 1
        if eff == "gain_mana":
            return 1
        if eff == "buff_friendly":
            return {1: 2, 2: 4}[val]
        if eff == "draw_self_damage":
            return 1
        if eff == "damage_per_card_played":
            return 2 + val
        if eff == "random_enemy_damage":
            return val
        if eff == "damage_split":
            return val
        if eff == "destroy_damaged":
            return 2
        if eff == "damage_per_hand_card":
            return 3 + 2 * val
        if eff == "recruit":
            return val + 2
        if eff == "buff_all_friendly":
            return 4 * val
        if eff == "swap_stats":
            return 2
        raise KeyError(eff)

    for c in R + L:
        if c["type"] != "minion":
            continue
        total = c["attack"] + c["health"] + len(c["keywords"]) \
            + pts(c["effect"], c["effect_value"]) \
            + pts(c["deathrattle"], c["deathrattle_value"])
        target = VANILLA[c["cost"]] + prem(c["cost"])
        if total != target:
            print(f"BUDGET OFF: {c['id']} total {total} target {target}")
    # Name uniqueness.
    names = Counter(c["name"] for c in R + L)
    print("dup names within Batch 3:", [n for n, k in names.items() if k > 1])
    print("Batch 3 self-check done")
