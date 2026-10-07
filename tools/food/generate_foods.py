#!/usr/bin/env python3
"""Genera il database locale degli alimenti generici (offline) per il logger (M9, ADR-009).

Valori per 100 g di parte edibile, arrotondati, da tabelle di composizione pubbliche
(CREA / USDA FoodData Central, alimenti crudi salvo indicazione). Sono valori medi: il logger
mostra la fonte "JEV generico" e l'utente può sempre creare un alimento personalizzato.

Uso:  python3 -I tools/food/generate_foods.py          (rigenera il JSON)
      python3 -I tools/food/generate_foods.py --check  (CI: fallisce se il JSON non è aggiornato)
"""
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = ROOT / "Packages/JevKit/Sources/Food/Resources/foods.json"

# id, nome, kcal, proteine, carboidrati, grassi, fibra
FOODS = [
    ("pasta_dry", "Pasta di semola (cruda)", 353, 12.5, 71.0, 1.5, 3.0),
    ("pasta_wholewheat_dry", "Pasta integrale (cruda)", 340, 13.4, 64.0, 2.5, 8.0),
    ("rice_white_raw", "Riso bianco (crudo)", 358, 6.7, 79.0, 0.6, 1.0),
    ("rice_basmati_raw", "Riso basmati (crudo)", 351, 8.0, 77.0, 0.8, 1.3),
    ("rice_brown_raw", "Riso integrale (crudo)", 362, 7.5, 76.0, 2.7, 3.4),
    ("oats_rolled", "Fiocchi d'avena", 372, 13.0, 60.0, 7.0, 10.0),
    ("bread_white", "Pane comune", 270, 8.5, 54.0, 1.5, 2.7),
    ("bread_wholewheat", "Pane integrale", 245, 9.5, 44.0, 2.4, 7.0),
    ("potato_raw", "Patate (crude)", 77, 2.0, 17.0, 0.1, 2.2),
    ("sweet_potato_raw", "Patate dolci (crude)", 86, 1.6, 20.0, 0.1, 3.0),
    ("corn_flakes", "Corn flakes", 370, 7.0, 84.0, 0.9, 3.0),
    ("chicken_breast_raw", "Petto di pollo (crudo)", 110, 23.0, 0.0, 1.5, 0.0),
    ("turkey_breast_raw", "Petto di tacchino (crudo)", 107, 24.0, 0.0, 1.0, 0.0),
    ("beef_lean_raw", "Manzo magro (crudo)", 130, 21.5, 0.0, 5.0, 0.0),
    ("beef_minced_raw", "Macinato di manzo 10% grassi (crudo)", 176, 20.0, 0.0, 10.0, 0.0),
    ("pork_loin_raw", "Lonza di maiale (cruda)", 143, 21.0, 0.0, 6.5, 0.0),
    ("salmon_raw", "Salmone (crudo)", 185, 20.0, 0.0, 11.5, 0.0),
    ("tuna_canned_water", "Tonno al naturale (sgocciolato)", 108, 25.0, 0.0, 1.0, 0.0),
    ("tuna_canned_oil", "Tonno sott'olio (sgocciolato)", 192, 25.0, 0.0, 10.0, 0.0),
    ("cod_raw", "Merluzzo (crudo)", 82, 18.0, 0.0, 0.7, 0.0),
    ("shrimp_raw", "Gamberi (crudi)", 85, 20.0, 0.2, 0.5, 0.0),
    ("egg_whole", "Uovo intero", 143, 12.6, 0.7, 9.5, 0.0),
    ("egg_white", "Albume d'uovo", 52, 11.0, 0.7, 0.2, 0.0),
    ("ham_cooked", "Prosciutto cotto", 140, 19.0, 1.0, 6.5, 0.0),
    ("bresaola", "Bresaola", 151, 32.0, 0.0, 2.0, 0.0),
    ("prosciutto_crudo", "Prosciutto crudo", 250, 26.0, 0.0, 16.0, 0.0),
    ("milk_skim", "Latte scremato", 35, 3.4, 5.0, 0.1, 0.0),
    ("milk_semi", "Latte parzialmente scremato", 46, 3.3, 5.0, 1.5, 0.0),
    ("milk_whole", "Latte intero", 64, 3.3, 4.8, 3.6, 0.0),
    ("yogurt_greek_0", "Yogurt greco 0%", 57, 10.0, 3.6, 0.2, 0.0),
    ("yogurt_greek_full", "Yogurt greco intero", 115, 9.0, 3.9, 7.0, 0.0),
    ("yogurt_plain", "Yogurt bianco intero", 66, 3.8, 4.5, 3.5, 0.0),
    ("skyr", "Skyr", 63, 11.0, 4.0, 0.2, 0.0),
    ("cottage_cheese", "Fiocchi di latte", 98, 11.5, 3.0, 4.3, 0.0),
    ("ricotta", "Ricotta vaccina", 146, 9.0, 3.5, 11.0, 0.0),
    ("mozzarella", "Mozzarella vaccina", 253, 18.7, 0.7, 19.5, 0.0),
    ("parmesan", "Parmigiano Reggiano", 392, 33.0, 0.0, 28.0, 0.0),
    ("whey_protein", "Proteine del siero (polvere)", 380, 78.0, 7.0, 5.0, 0.0),
    ("tofu", "Tofu", 76, 8.1, 1.9, 4.8, 0.3),
    ("chickpeas_cooked", "Ceci (cotti)", 164, 8.9, 27.0, 2.6, 7.6),
    ("lentils_cooked", "Lenticchie (cotte)", 116, 9.0, 20.0, 0.4, 7.9),
    ("beans_cooked", "Fagioli borlotti (cotti)", 127, 8.7, 22.8, 0.5, 6.4),
    ("peas_frozen", "Piselli surgelati", 77, 5.4, 12.0, 0.4, 5.0),
    ("olive_oil", "Olio extravergine d'oliva", 899, 0.0, 0.0, 99.9, 0.0),
    ("butter", "Burro", 717, 0.9, 0.1, 81.0, 0.0),
    ("almonds", "Mandorle", 579, 21.0, 9.5, 50.0, 12.5),
    ("walnuts", "Noci", 654, 15.0, 7.0, 65.0, 6.7),
    ("peanut_butter", "Burro d'arachidi", 588, 25.0, 16.0, 50.0, 6.0),
    ("dark_chocolate_70", "Cioccolato fondente 70%", 598, 7.8, 34.0, 43.0, 11.0),
    ("apple", "Mela", 52, 0.3, 12.0, 0.2, 2.4),
    ("banana", "Banana", 89, 1.1, 20.0, 0.3, 2.6),
    ("orange", "Arancia", 47, 0.9, 9.0, 0.1, 2.4),
    ("strawberries", "Fragole", 32, 0.7, 5.5, 0.3, 2.0),
    ("blueberries", "Mirtilli", 57, 0.7, 12.0, 0.3, 2.4),
    ("kiwi", "Kiwi", 61, 1.1, 12.0, 0.5, 3.0),
    ("pear", "Pera", 57, 0.4, 13.0, 0.1, 3.1),
    ("grapes", "Uva", 69, 0.7, 16.0, 0.2, 0.9),
    ("dates_dried", "Datteri secchi", 282, 2.5, 63.0, 0.4, 8.0),
    ("tomato", "Pomodoro", 18, 0.9, 3.0, 0.2, 1.2),
    ("tomato_passata", "Passata di pomodoro", 30, 1.4, 5.0, 0.2, 1.5),
    ("lettuce", "Lattuga", 15, 1.4, 2.0, 0.2, 1.3),
    ("spinach", "Spinaci", 23, 2.9, 1.4, 0.4, 2.2),
    ("broccoli", "Broccoli", 34, 2.8, 4.5, 0.4, 2.6),
    ("zucchini", "Zucchine", 17, 1.2, 2.1, 0.3, 1.0),
    ("carrot", "Carote", 41, 0.9, 7.6, 0.2, 2.8),
    ("bell_pepper", "Peperoni", 26, 1.0, 4.6, 0.3, 2.1),
    ("eggplant", "Melanzane", 25, 1.0, 3.5, 0.2, 3.0),
    ("onion", "Cipolla", 40, 1.1, 8.0, 0.1, 1.7),
    ("mushrooms", "Funghi champignon", 22, 3.1, 1.0, 0.3, 1.0),
    ("avocado", "Avocado", 160, 2.0, 1.8, 14.7, 6.7),
    ("pizza_margherita", "Pizza margherita", 254, 11.0, 32.0, 9.0, 2.0),
    ("honey", "Miele", 304, 0.3, 82.0, 0.0, 0.2),
    ("sugar", "Zucchero", 400, 0.0, 100.0, 0.0, 0.0),
    ("jam", "Marmellata", 250, 0.4, 61.0, 0.1, 1.0),
    ("rice_cakes", "Gallette di riso", 387, 8.0, 81.0, 2.8, 4.2),
    ("crackers", "Cracker", 428, 9.4, 70.0, 11.0, 3.0),
    ("granola", "Muesli croccante", 450, 10.0, 64.0, 16.0, 7.0),
    ("orange_juice", "Succo d'arancia", 45, 0.7, 10.4, 0.2, 0.2),
    ("beer", "Birra", 43, 0.5, 3.6, 0.0, 0.0),
    ("wine_red", "Vino rosso", 85, 0.1, 2.6, 0.0, 0.0),
]


def build():
    foods = []
    for fid, name, kcal, protein, carbs, fat, fiber in FOODS:
        assert protein + carbs + fat <= 100.0001, fid
        assert 0 <= kcal <= 900, fid
        foods.append({
            "id": fid, "name": name, "energyKcal": kcal, "proteinGrams": protein,
            "carbohydrateGrams": carbs, "fatGrams": fat, "fiberGrams": fiber,
        })
    ids = [f["id"] for f in foods]
    assert len(ids) == len(set(ids)), "id duplicati"
    return json.dumps({"schemaVersion": 1, "foods": foods}, ensure_ascii=False, indent=1) + "\n"


def main():
    text = build()
    if "--check" in sys.argv:
        if not OUT.exists() or OUT.read_text(encoding="utf-8") != text:
            sys.exit("foods.json non aggiornato: esegui tools/food/generate_foods.py")
        print(f"foods.json aggiornato ({len(FOODS)} alimenti)")
        return
    OUT.write_text(text, encoding="utf-8")
    print(f"scritti {len(FOODS)} alimenti")


if __name__ == "__main__":
    main()
