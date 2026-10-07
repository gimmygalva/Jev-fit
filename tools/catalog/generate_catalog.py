#!/usr/bin/env python3
"""Genera Packages/JevEngines/Sources/ExerciseCatalog/Resources/exercises.json.

Catalogo ORIGINALE del progetto (nomi generici di esercizi, classificazioni scritte da zero):
nessun testo, immagine o database copiato da altre app (ARCHITECTURE_PLAN §8.6).

Colonne della tabella:
  id, nome, schema di movimento, attrezzatura, muscoli primari, secondari, meccanica (C/I),
  difficoltà (1 principiante … 3 avanzato), tipo di carico, fatica (0,5–1,3), stimolo (0,6–1,2),
  incremento di carico in kg, frazione del peso corporeo (solo bodyweight/assisted),
  aree controindicate, lateralità (B/U).

Uso:  python3 -I tools/catalog/generate_catalog.py           (scrive il JSON)
      python3 -I tools/catalog/generate_catalog.py --check   (CI: fallisce se non aggiornato)
"""
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "Packages/JevEngines/Sources/ExerciseCatalog/Resources/exercises.json"

MUSCLES = {"chest", "lats", "upper_back", "front_delts", "side_delts", "rear_delts", "biceps", "triceps",
           "forearms", "abs", "obliques", "lower_back", "glutes", "quads", "hamstrings", "adductors", "calves"}
EQUIPMENT = {"barbell", "dumbbell", "kettlebell", "cable", "machine", "smith_machine", "ez_bar", "trap_bar",
             "pull_up_bar", "dip_station", "bench", "resistance_band", "bodyweight"}
AREAS = {"shoulder", "elbow", "wrist", "neck", "lower_back", "hip", "knee", "ankle", "other"}
PATTERNS = {"horizontal_push", "vertical_push", "horizontal_pull", "vertical_pull", "squat", "lunge", "hinge",
            "hip_extension", "knee_extension", "knee_flexion", "hip_adduction", "hip_abduction", "calf_raise",
            "elbow_flexion", "elbow_extension", "shoulder_isolation", "shrug", "wrist", "carry", "core_flexion",
            "core_stability", "core_rotation", "fly"}

E = "external"; BW = "bodyweight"; AS = "assisted"; T = "timed"

# id, nome, schema, attrezzatura, primari, secondari, mecc, diff, carico, fatica, stimolo, incr, frazione, controind., lat
TABLE = [
    # Petto ---------------------------------------------------------------------------------
    ("barbell_bench_press", "Panca piana con bilanciere", "horizontal_push", "barbell bench", "chest", "triceps front_delts", "C", 2, E, 1.2, 1.0, 2.5, None, "shoulder", "B"),
    ("incline_barbell_bench_press", "Panca inclinata con bilanciere", "horizontal_push", "barbell bench", "chest", "front_delts triceps", "C", 2, E, 1.15, 1.0, 2.5, None, "shoulder", "B"),
    ("decline_barbell_bench_press", "Panca declinata con bilanciere", "horizontal_push", "barbell bench", "chest", "triceps", "C", 2, E, 1.1, 0.9, 2.5, None, "shoulder", "B"),
    ("dumbbell_bench_press", "Distensioni su panca piana con manubri", "horizontal_push", "dumbbell bench", "chest", "triceps front_delts", "C", 1, E, 1.05, 1.05, 2.0, None, "shoulder", "B"),
    ("incline_dumbbell_press", "Distensioni su panca inclinata con manubri", "horizontal_push", "dumbbell bench", "chest", "front_delts triceps", "C", 1, E, 1.0, 1.05, 2.0, None, "shoulder", "B"),
    ("smith_bench_press", "Panca piana al multipower", "horizontal_push", "smith_machine bench", "chest", "triceps front_delts", "C", 1, E, 1.0, 0.95, 2.5, None, "shoulder", "B"),
    ("smith_incline_press", "Panca inclinata al multipower", "horizontal_push", "smith_machine bench", "chest", "front_delts triceps", "C", 1, E, 0.95, 0.95, 2.5, None, "shoulder", "B"),
    ("machine_chest_press", "Chest press alla macchina", "horizontal_push", "machine", "chest", "triceps front_delts", "C", 1, E, 0.85, 0.95, 5.0, None, "", "B"),
    ("incline_machine_press", "Chest press inclinata alla macchina", "horizontal_push", "machine", "chest", "front_delts triceps", "C", 1, E, 0.85, 0.95, 5.0, None, "", "B"),
    ("dumbbell_floor_press", "Floor press con manubri", "horizontal_push", "dumbbell", "chest", "triceps", "C", 1, E, 0.85, 0.85, 2.0, None, "", "B"),
    ("band_chest_press", "Distensioni con elastico", "horizontal_push", "resistance_band", "chest", "triceps front_delts", "C", 1, E, 0.6, 0.7, 1.0, None, "", "B"),
    ("push_up", "Piegamenti sulle braccia", "horizontal_push", "bodyweight", "chest", "triceps front_delts abs", "C", 1, BW, 0.75, 0.85, 2.5, 0.64, "wrist", "B"),
    ("deficit_push_up", "Piegamenti con deficit", "horizontal_push", "bodyweight", "chest", "triceps front_delts", "C", 2, BW, 0.8, 0.9, 2.5, 0.66, "wrist shoulder", "B"),
    ("incline_push_up", "Piegamenti con mani rialzate", "horizontal_push", "bench", "chest", "triceps front_delts", "C", 1, BW, 0.6, 0.75, 2.5, 0.5, "wrist", "B"),
    ("dip", "Dip alle parallele", "horizontal_push", "dip_station", "chest triceps", "front_delts", "C", 2, BW, 1.1, 1.0, 2.5, 0.95, "shoulder elbow", "B"),
    ("assisted_dip", "Dip assistiti alla macchina", "horizontal_push", "machine", "chest triceps", "front_delts", "C", 1, AS, 0.9, 0.9, 5.0, 0.95, "shoulder", "B"),
    ("dumbbell_fly", "Croci su panca con manubri", "fly", "dumbbell bench", "chest", "front_delts", "I", 1, E, 0.8, 0.9, 2.0, None, "shoulder", "B"),
    ("cable_fly", "Croci ai cavi", "fly", "cable", "chest", "front_delts", "I", 1, E, 0.7, 1.0, 2.5, None, "", "B"),
    ("low_to_high_cable_fly", "Croci ai cavi dal basso", "fly", "cable", "chest", "front_delts", "I", 1, E, 0.7, 1.0, 2.5, None, "", "B"),
    ("pec_deck", "Pectoral machine", "fly", "machine", "chest", "", "I", 1, E, 0.7, 1.0, 5.0, None, "", "B"),
    # Spalle --------------------------------------------------------------------------------
    ("overhead_press", "Lento avanti con bilanciere", "vertical_push", "barbell", "front_delts", "triceps side_delts upper_back abs", "C", 2, E, 1.15, 1.0, 2.5, None, "shoulder lower_back", "B"),
    ("seated_dumbbell_press", "Distensioni sopra la testa con manubri da seduto", "vertical_push", "dumbbell bench", "front_delts", "triceps side_delts", "C", 1, E, 1.0, 1.0, 2.0, None, "shoulder", "B"),
    ("standing_dumbbell_press", "Distensioni sopra la testa con manubri in piedi", "vertical_push", "dumbbell", "front_delts", "triceps side_delts abs", "C", 2, E, 1.05, 1.0, 2.0, None, "shoulder", "B"),
    ("machine_shoulder_press", "Shoulder press alla macchina", "vertical_push", "machine", "front_delts", "triceps side_delts", "C", 1, E, 0.85, 0.95, 5.0, None, "shoulder", "B"),
    ("smith_overhead_press", "Lento avanti al multipower", "vertical_push", "smith_machine bench", "front_delts", "triceps side_delts", "C", 1, E, 0.95, 0.95, 2.5, None, "shoulder", "B"),
    ("landmine_press", "Landmine press", "vertical_push", "barbell", "front_delts", "chest triceps", "C", 1, E, 0.85, 0.9, 2.5, None, "", "U"),
    ("arnold_press", "Arnold press", "vertical_push", "dumbbell bench", "front_delts", "side_delts triceps", "C", 2, E, 0.95, 1.0, 2.0, None, "shoulder", "B"),
    ("kettlebell_press", "Distensione sopra la testa con kettlebell", "vertical_push", "kettlebell", "front_delts", "triceps side_delts abs", "C", 2, E, 0.95, 0.9, 4.0, None, "shoulder", "U"),
    ("pike_push_up", "Piegamenti a V", "vertical_push", "bodyweight", "front_delts", "triceps side_delts", "C", 2, BW, 0.85, 0.85, 2.5, 0.5, "shoulder wrist", "B"),
    ("lateral_raise", "Alzate laterali con manubri", "shoulder_isolation", "dumbbell", "side_delts", "", "I", 1, E, 0.6, 1.0, 1.0, None, "", "B"),
    ("cable_lateral_raise", "Alzate laterali al cavo", "shoulder_isolation", "cable", "side_delts", "", "I", 1, E, 0.6, 1.05, 1.25, None, "", "U"),
    ("machine_lateral_raise", "Alzate laterali alla macchina", "shoulder_isolation", "machine", "side_delts", "", "I", 1, E, 0.6, 1.0, 2.5, None, "", "B"),
    ("band_lateral_raise", "Alzate laterali con elastico", "shoulder_isolation", "resistance_band", "side_delts", "", "I", 1, E, 0.5, 0.8, 1.0, None, "", "B"),
    ("front_raise", "Alzate frontali con manubri", "shoulder_isolation", "dumbbell", "front_delts", "", "I", 1, E, 0.6, 0.85, 1.0, None, "", "B"),
    ("rear_delt_fly", "Alzate posteriori a busto flesso", "shoulder_isolation", "dumbbell", "rear_delts", "upper_back", "I", 1, E, 0.6, 0.95, 1.0, None, "lower_back", "B"),
    ("reverse_pec_deck", "Reverse fly alla macchina", "shoulder_isolation", "machine", "rear_delts", "upper_back", "I", 1, E, 0.6, 1.0, 2.5, None, "", "B"),
    ("face_pull", "Face pull al cavo", "shoulder_isolation", "cable", "rear_delts", "upper_back", "I", 1, E, 0.6, 1.0, 2.5, None, "", "B"),
    ("cable_rear_delt_fly", "Croci inverse ai cavi", "shoulder_isolation", "cable", "rear_delts", "upper_back", "I", 1, E, 0.6, 1.0, 1.25, None, "", "B"),
    ("upright_row", "Tirate al mento con bilanciere EZ", "shoulder_isolation", "ez_bar", "side_delts", "upper_back front_delts", "C", 2, E, 0.8, 0.9, 2.5, None, "shoulder", "B"),
    ("band_pull_apart", "Aperture con elastico", "shoulder_isolation", "resistance_band", "rear_delts", "upper_back", "I", 1, E, 0.5, 0.8, 1.0, None, "", "B"),
    # Dorso: tirate verticali ---------------------------------------------------------------
    ("pull_up", "Trazioni alla sbarra a presa prona", "vertical_pull", "pull_up_bar", "lats", "biceps upper_back rear_delts forearms", "C", 2, BW, 1.1, 1.05, 2.5, 1.0, "shoulder elbow", "B"),
    ("chin_up", "Trazioni a presa supina", "vertical_pull", "pull_up_bar", "lats", "biceps upper_back forearms", "C", 2, BW, 1.1, 1.05, 2.5, 1.0, "shoulder elbow", "B"),
    ("neutral_grip_pull_up", "Trazioni a presa neutra", "vertical_pull", "pull_up_bar", "lats", "biceps upper_back forearms", "C", 2, BW, 1.05, 1.05, 2.5, 1.0, "elbow", "B"),
    ("assisted_pull_up", "Trazioni assistite alla macchina", "vertical_pull", "machine", "lats", "biceps upper_back", "C", 1, AS, 0.9, 1.0, 5.0, 1.0, "", "B"),
    ("band_assisted_pull_up", "Trazioni assistite con elastico", "vertical_pull", "pull_up_bar resistance_band", "lats", "biceps upper_back", "C", 1, AS, 0.95, 1.0, 5.0, 1.0, "", "B"),
    ("lat_pulldown", "Lat machine a presa larga", "vertical_pull", "cable", "lats", "biceps rear_delts upper_back", "C", 1, E, 0.9, 1.0, 5.0, None, "", "B"),
    ("close_grip_pulldown", "Lat machine a presa stretta", "vertical_pull", "cable", "lats", "biceps upper_back", "C", 1, E, 0.9, 1.0, 5.0, None, "", "B"),
    ("single_arm_pulldown", "Lat machine a un braccio", "vertical_pull", "cable", "lats", "biceps", "C", 1, E, 0.8, 1.05, 2.5, None, "", "U"),
    ("straight_arm_pulldown", "Pullover al cavo a braccia tese", "vertical_pull", "cable", "lats", "triceps", "I", 1, E, 0.7, 0.95, 2.5, None, "", "B"),
    ("dumbbell_pullover", "Pullover con manubrio", "vertical_pull", "dumbbell bench", "lats", "chest triceps", "I", 1, E, 0.75, 0.85, 2.0, None, "shoulder", "B"),
    # Dorso: tirate orizzontali -------------------------------------------------------------
    ("barbell_row", "Rematore con bilanciere", "horizontal_pull", "barbell", "upper_back lats", "rear_delts biceps lower_back", "C", 2, E, 1.2, 1.0, 2.5, None, "lower_back", "B"),
    ("pendlay_row", "Rematore Pendlay", "horizontal_pull", "barbell", "upper_back lats", "rear_delts biceps lower_back", "C", 3, E, 1.2, 1.0, 2.5, None, "lower_back", "B"),
    ("dumbbell_row", "Rematore con manubrio a un braccio", "horizontal_pull", "dumbbell bench", "lats upper_back", "rear_delts biceps", "C", 1, E, 0.9, 1.05, 2.0, None, "", "U"),
    ("chest_supported_row", "Rematore con petto in appoggio", "horizontal_pull", "dumbbell bench", "upper_back lats", "rear_delts biceps", "C", 1, E, 0.85, 1.05, 2.0, None, "", "B"),
    ("seated_cable_row", "Pulley basso", "horizontal_pull", "cable", "upper_back lats", "biceps rear_delts", "C", 1, E, 0.9, 1.0, 5.0, None, "", "B"),
    ("machine_row", "Rematore alla macchina", "horizontal_pull", "machine", "upper_back lats", "biceps rear_delts", "C", 1, E, 0.8, 1.0, 5.0, None, "", "B"),
    ("t_bar_row", "Rematore T-bar", "horizontal_pull", "barbell", "upper_back lats", "biceps lower_back", "C", 2, E, 1.1, 1.0, 2.5, None, "lower_back", "B"),
    ("inverted_row", "Rematore inverso", "horizontal_pull", "pull_up_bar", "upper_back lats", "biceps rear_delts", "C", 1, BW, 0.75, 0.85, 2.5, 0.6, "", "B"),
    ("kettlebell_row", "Rematore con kettlebell", "horizontal_pull", "kettlebell", "lats upper_back", "biceps", "C", 1, E, 0.85, 0.9, 4.0, None, "", "U"),
    ("band_row", "Rematore con elastico", "horizontal_pull", "resistance_band", "upper_back lats", "biceps", "C", 1, E, 0.6, 0.7, 1.0, None, "", "B"),
    ("barbell_shrug", "Scrollate con bilanciere", "shrug", "barbell", "upper_back", "forearms", "I", 1, E, 0.7, 0.95, 2.5, None, "neck", "B"),
    ("dumbbell_shrug", "Scrollate con manubri", "shrug", "dumbbell", "upper_back", "forearms", "I", 1, E, 0.65, 0.95, 2.0, None, "neck", "B"),
    ("trap_bar_shrug", "Scrollate con trap bar", "shrug", "trap_bar", "upper_back", "forearms", "I", 1, E, 0.7, 0.95, 5.0, None, "neck", "B"),
    # Gambe: squat --------------------------------------------------------------------------
    ("back_squat", "Squat con bilanciere", "squat", "barbell", "quads glutes", "adductors lower_back", "C", 2, E, 1.3, 1.0, 2.5, None, "knee lower_back", "B"),
    ("front_squat", "Front squat", "squat", "barbell", "quads", "glutes upper_back abs", "C", 3, E, 1.25, 1.0, 2.5, None, "knee wrist", "B"),
    ("goblet_squat", "Goblet squat con manubrio", "squat", "dumbbell", "quads glutes", "adductors abs", "C", 1, E, 0.9, 0.9, 2.0, None, "knee", "B"),
    ("kettlebell_goblet_squat", "Goblet squat con kettlebell", "squat", "kettlebell", "quads glutes", "adductors abs", "C", 1, E, 0.9, 0.9, 4.0, None, "knee", "B"),
    ("smith_squat", "Squat al multipower", "squat", "smith_machine", "quads glutes", "adductors", "C", 1, E, 1.1, 0.95, 2.5, None, "knee", "B"),
    ("hack_squat", "Hack squat alla macchina", "squat", "machine", "quads", "glutes adductors", "C", 1, E, 1.1, 1.05, 5.0, None, "knee", "B"),
    ("leg_press", "Leg press", "squat", "machine", "quads glutes", "adductors", "C", 1, E, 1.05, 1.0, 5.0, None, "knee", "B"),
    ("single_leg_press", "Leg press a una gamba", "squat", "machine", "quads glutes", "adductors", "C", 1, E, 0.9, 1.0, 5.0, None, "knee", "U"),
    ("bodyweight_squat", "Squat a corpo libero", "squat", "bodyweight", "quads glutes", "adductors", "C", 1, BW, 0.6, 0.6, 2.5, 0.7, "knee", "B"),
    # Gambe: affondi ------------------------------------------------------------------------
    ("bulgarian_split_squat", "Split squat bulgaro con manubri", "lunge", "dumbbell bench", "quads glutes", "adductors", "C", 2, E, 1.1, 1.05, 2.0, None, "knee", "U"),
    ("walking_lunge", "Affondi in camminata con manubri", "lunge", "dumbbell", "quads glutes", "adductors hamstrings", "C", 2, E, 1.05, 1.0, 2.0, None, "knee", "U"),
    ("reverse_lunge", "Affondi indietro con manubri", "lunge", "dumbbell", "quads glutes", "adductors", "C", 1, E, 1.0, 1.0, 2.0, None, "knee", "U"),
    ("barbell_lunge", "Affondi con bilanciere", "lunge", "barbell", "quads glutes", "adductors hamstrings", "C", 2, E, 1.1, 1.0, 2.5, None, "knee", "U"),
    ("step_up", "Step-up su panca con manubri", "lunge", "dumbbell bench", "quads glutes", "hamstrings", "C", 1, E, 0.9, 0.95, 2.0, None, "knee", "U"),
    ("bodyweight_lunge", "Affondi a corpo libero", "lunge", "bodyweight", "quads glutes", "adductors", "C", 1, BW, 0.6, 0.65, 2.5, 0.7, "knee", "U"),
    ("smith_split_squat", "Split squat al multipower", "lunge", "smith_machine", "quads glutes", "adductors", "C", 1, E, 1.0, 1.0, 2.5, None, "knee", "U"),
    ("leg_extension", "Leg extension", "knee_extension", "machine", "quads", "", "I", 1, E, 0.7, 1.0, 5.0, None, "knee", "B"),
    # Gambe: stacchi e cerniera d'anca ------------------------------------------------------
    ("conventional_deadlift", "Stacco da terra", "hinge", "barbell", "hamstrings glutes lower_back", "quads upper_back forearms", "C", 3, E, 1.3, 0.95, 5.0, None, "lower_back", "B"),
    ("romanian_deadlift", "Stacco rumeno con bilanciere", "hinge", "barbell", "hamstrings glutes", "lower_back forearms", "C", 2, E, 1.2, 1.05, 2.5, None, "lower_back", "B"),
    ("dumbbell_romanian_deadlift", "Stacco rumeno con manubri", "hinge", "dumbbell", "hamstrings glutes", "lower_back forearms", "C", 1, E, 1.05, 1.0, 2.0, None, "lower_back", "B"),
    ("trap_bar_deadlift", "Stacco con trap bar", "hinge", "trap_bar", "quads glutes hamstrings", "lower_back upper_back forearms", "C", 2, E, 1.25, 1.0, 5.0, None, "lower_back", "B"),
    ("sumo_deadlift", "Stacco sumo", "hinge", "barbell", "glutes adductors hamstrings", "quads lower_back forearms", "C", 3, E, 1.25, 0.95, 5.0, None, "lower_back hip", "B"),
    ("single_leg_romanian_deadlift", "Stacco rumeno a una gamba con manubrio", "hinge", "dumbbell", "hamstrings glutes", "lower_back", "C", 2, E, 0.9, 0.95, 2.0, None, "", "U"),
    ("good_morning", "Good morning con bilanciere", "hinge", "barbell", "hamstrings lower_back", "glutes", "C", 2, E, 1.1, 0.9, 2.5, None, "lower_back", "B"),
    ("kettlebell_deadlift", "Stacco con kettlebell", "hinge", "kettlebell", "glutes hamstrings", "quads lower_back", "C", 1, E, 0.9, 0.85, 4.0, None, "lower_back", "B"),
    ("kettlebell_swing", "Swing con kettlebell", "hinge", "kettlebell", "glutes hamstrings", "lower_back abs", "C", 2, E, 0.9, 0.8, 4.0, None, "lower_back", "B"),
    ("cable_pull_through", "Pull-through al cavo", "hinge", "cable", "glutes hamstrings", "", "C", 1, E, 0.7, 0.85, 2.5, None, "", "B"),
    ("back_extension", "Iperestensioni su panca", "hinge", "bench", "lower_back glutes", "hamstrings", "I", 1, BW, 0.7, 0.85, 2.5, 0.5, "lower_back", "B"),
    # Glutei --------------------------------------------------------------------------------
    ("hip_thrust", "Hip thrust con bilanciere", "hip_extension", "barbell bench", "glutes", "hamstrings", "C", 1, E, 0.9, 1.05, 5.0, None, "", "B"),
    ("machine_hip_thrust", "Hip thrust alla macchina", "hip_extension", "machine", "glutes", "hamstrings", "C", 1, E, 0.85, 1.05, 5.0, None, "", "B"),
    ("glute_bridge", "Ponte per glutei", "hip_extension", "bodyweight", "glutes", "hamstrings", "I", 1, BW, 0.5, 0.65, 2.5, 0.4, "", "B"),
    ("single_leg_hip_thrust", "Hip thrust a una gamba", "hip_extension", "bench", "glutes", "hamstrings", "I", 1, BW, 0.6, 0.8, 2.5, 0.5, "", "U"),
    ("cable_kickback", "Slanci posteriori al cavo", "hip_extension", "cable", "glutes", "hamstrings", "I", 1, E, 0.55, 0.85, 1.25, None, "", "U"),
    ("hip_abduction", "Abduzioni alla macchina", "hip_abduction", "machine", "glutes", "", "I", 1, E, 0.5, 0.9, 5.0, None, "", "B"),
    ("band_hip_abduction", "Abduzioni con elastico", "hip_abduction", "resistance_band", "glutes", "", "I", 1, E, 0.45, 0.7, 1.0, None, "", "B"),
    # Femorali ------------------------------------------------------------------------------
    ("lying_leg_curl", "Leg curl sdraiato", "knee_flexion", "machine", "hamstrings", "calves", "I", 1, E, 0.75, 1.0, 5.0, None, "knee", "B"),
    ("seated_leg_curl", "Leg curl da seduto", "knee_flexion", "machine", "hamstrings", "", "I", 1, E, 0.75, 1.05, 5.0, None, "knee", "B"),
    ("nordic_curl", "Nordic curl", "knee_flexion", "bodyweight", "hamstrings", "", "I", 3, BW, 1.0, 1.0, 2.5, 0.6, "knee", "B"),
    ("dumbbell_leg_curl", "Leg curl con manubrio", "knee_flexion", "dumbbell bench", "hamstrings", "", "I", 1, E, 0.65, 0.85, 2.0, None, "knee", "B"),
    ("band_leg_curl", "Leg curl con elastico", "knee_flexion", "resistance_band", "hamstrings", "", "I", 1, E, 0.5, 0.7, 1.0, None, "knee", "B"),
    # Adduttori -----------------------------------------------------------------------------
    ("hip_adduction", "Adduzioni alla macchina", "hip_adduction", "machine", "adductors", "", "I", 1, E, 0.55, 0.95, 5.0, None, "hip", "B"),
    ("cable_adduction", "Adduzioni al cavo", "hip_adduction", "cable", "adductors", "", "I", 1, E, 0.5, 0.85, 1.25, None, "hip", "U"),
    ("copenhagen_plank", "Copenhagen plank", "hip_adduction", "bench", "adductors", "obliques", "I", 2, T, 0.6, 0.85, 0, None, "hip", "U"),
    # Polpacci ------------------------------------------------------------------------------
    ("standing_calf_raise", "Calf raise in piedi alla macchina", "calf_raise", "machine", "calves", "", "I", 1, E, 0.6, 1.0, 5.0, None, "ankle", "B"),
    ("seated_calf_raise", "Calf raise da seduto", "calf_raise", "machine", "calves", "", "I", 1, E, 0.55, 0.95, 5.0, None, "ankle", "B"),
    ("leg_press_calf_raise", "Calf raise alla leg press", "calf_raise", "machine", "calves", "", "I", 1, E, 0.6, 1.0, 5.0, None, "ankle", "B"),
    ("smith_calf_raise", "Calf raise al multipower", "calf_raise", "smith_machine", "calves", "", "I", 1, E, 0.6, 0.95, 2.5, None, "ankle", "B"),
    ("single_leg_calf_raise", "Calf raise a una gamba con manubrio", "calf_raise", "dumbbell", "calves", "", "I", 1, E, 0.55, 0.95, 2.0, None, "ankle", "U"),
    ("bodyweight_calf_raise", "Calf raise a corpo libero", "calf_raise", "bodyweight", "calves", "", "I", 1, BW, 0.45, 0.7, 2.5, 1.0, "ankle", "B"),
    # Bicipiti ------------------------------------------------------------------------------
    ("barbell_curl", "Curl con bilanciere", "elbow_flexion", "barbell", "biceps", "forearms", "I", 1, E, 0.7, 1.0, 2.5, None, "elbow wrist", "B"),
    ("ez_bar_curl", "Curl con bilanciere EZ", "elbow_flexion", "ez_bar", "biceps", "forearms", "I", 1, E, 0.7, 1.0, 2.5, None, "elbow", "B"),
    ("dumbbell_curl", "Curl con manubri", "elbow_flexion", "dumbbell", "biceps", "forearms", "I", 1, E, 0.65, 1.0, 2.0, None, "elbow", "B"),
    ("hammer_curl", "Curl a martello", "elbow_flexion", "dumbbell", "biceps", "forearms", "I", 1, E, 0.65, 0.95, 2.0, None, "elbow", "B"),
    ("incline_dumbbell_curl", "Curl su panca inclinata", "elbow_flexion", "dumbbell bench", "biceps", "", "I", 1, E, 0.65, 1.05, 2.0, None, "elbow shoulder", "B"),
    ("preacher_curl", "Curl alla panca Scott", "elbow_flexion", "ez_bar bench", "biceps", "", "I", 1, E, 0.7, 1.05, 2.5, None, "elbow", "B"),
    ("cable_curl", "Curl al cavo", "elbow_flexion", "cable", "biceps", "forearms", "I", 1, E, 0.6, 1.0, 2.5, None, "elbow", "B"),
    ("machine_curl", "Curl alla macchina", "elbow_flexion", "machine", "biceps", "", "I", 1, E, 0.6, 1.0, 2.5, None, "elbow", "B"),
    ("concentration_curl", "Curl di concentrazione", "elbow_flexion", "dumbbell bench", "biceps", "", "I", 1, E, 0.55, 0.95, 1.0, None, "elbow", "U"),
    ("band_curl", "Curl con elastico", "elbow_flexion", "resistance_band", "biceps", "forearms", "I", 1, E, 0.5, 0.7, 1.0, None, "", "B"),
    # Tricipiti -----------------------------------------------------------------------------
    ("close_grip_bench_press", "Panca a presa stretta", "elbow_extension", "barbell bench", "triceps chest", "front_delts", "C", 2, E, 1.05, 1.0, 2.5, None, "elbow shoulder wrist", "B"),
    ("skull_crusher", "French press con bilanciere EZ", "elbow_extension", "ez_bar bench", "triceps", "", "I", 1, E, 0.75, 1.0, 2.5, None, "elbow", "B"),
    ("overhead_cable_extension", "Estensioni sopra la testa al cavo", "elbow_extension", "cable", "triceps", "", "I", 1, E, 0.65, 1.05, 2.5, None, "elbow shoulder", "B"),
    ("triceps_pushdown", "Pushdown ai cavi", "elbow_extension", "cable", "triceps", "", "I", 1, E, 0.6, 1.0, 2.5, None, "elbow", "B"),
    ("dumbbell_overhead_extension", "Estensioni sopra la testa con manubrio", "elbow_extension", "dumbbell", "triceps", "", "I", 1, E, 0.65, 1.0, 2.0, None, "elbow shoulder", "B"),
    ("machine_triceps_extension", "Estensioni per tricipiti alla macchina", "elbow_extension", "machine", "triceps", "", "I", 1, E, 0.6, 1.0, 2.5, None, "elbow", "B"),
    ("band_triceps_extension", "Estensioni per tricipiti con elastico", "elbow_extension", "resistance_band", "triceps", "", "I", 1, E, 0.5, 0.7, 1.0, None, "", "B"),
    ("bench_dip", "Dip tra due panche", "elbow_extension", "bench", "triceps", "chest front_delts", "C", 1, BW, 0.7, 0.75, 2.5, 0.6, "shoulder wrist", "B"),
    ("diamond_push_up", "Piegamenti a presa stretta", "elbow_extension", "bodyweight", "triceps", "chest front_delts", "C", 2, BW, 0.75, 0.85, 2.5, 0.64, "wrist elbow", "B"),
    # Avambracci e trasporti ----------------------------------------------------------------
    ("wrist_curl", "Curl per i polsi con manubri", "wrist", "dumbbell bench", "forearms", "", "I", 1, E, 0.45, 0.85, 1.0, None, "wrist", "B"),
    ("reverse_curl", "Curl inverso con bilanciere EZ", "wrist", "ez_bar", "forearms", "biceps", "I", 1, E, 0.55, 0.85, 2.5, None, "wrist elbow", "B"),
    ("farmer_carry", "Camminata del contadino", "carry", "dumbbell", "forearms upper_back", "abs obliques glutes", "C", 1, T, 0.9, 0.85, 0, None, "", "B"),
    ("suitcase_carry", "Camminata con un manubrio", "carry", "dumbbell", "obliques forearms", "abs", "C", 1, T, 0.7, 0.85, 0, None, "", "U"),
    ("dead_hang", "Sospensione alla sbarra", "carry", "pull_up_bar", "forearms", "lats", "I", 1, T, 0.5, 0.7, 0, None, "shoulder", "B"),
    # Core ----------------------------------------------------------------------------------
    ("plank", "Plank", "core_stability", "bodyweight", "abs", "obliques", "I", 1, T, 0.4, 0.7, 0, None, "", "B"),
    ("side_plank", "Plank laterale", "core_stability", "bodyweight", "obliques", "abs", "I", 1, T, 0.4, 0.75, 0, None, "", "U"),
    ("hollow_hold", "Hollow hold", "core_stability", "bodyweight", "abs", "", "I", 2, T, 0.45, 0.8, 0, None, "lower_back", "B"),
    ("dead_bug", "Dead bug", "core_stability", "bodyweight", "abs", "obliques", "I", 1, BW, 0.35, 0.7, 2.5, 0.15, "", "B"),
    ("bird_dog", "Bird dog", "core_stability", "bodyweight", "lower_back", "glutes abs", "I", 1, T, 0.3, 0.6, 0, None, "", "B"),
    ("pallof_press", "Pallof press al cavo", "core_rotation", "cable", "obliques", "abs", "I", 1, E, 0.4, 0.8, 1.25, None, "", "U"),
    ("cable_woodchop", "Woodchop al cavo", "core_rotation", "cable", "obliques", "abs", "I", 1, E, 0.45, 0.8, 1.25, None, "lower_back", "U"),
    ("russian_twist", "Russian twist con manubrio", "core_rotation", "dumbbell", "obliques", "abs", "I", 1, E, 0.45, 0.7, 1.0, None, "lower_back", "B"),
    ("hanging_leg_raise", "Sollevamento gambe alla sbarra", "core_flexion", "pull_up_bar", "abs", "obliques forearms", "I", 2, BW, 0.6, 1.0, 2.5, 0.35, "", "B"),
    ("cable_crunch", "Crunch al cavo", "core_flexion", "cable", "abs", "obliques", "I", 1, E, 0.5, 1.0, 2.5, None, "", "B"),
    ("machine_crunch", "Crunch alla macchina", "core_flexion", "machine", "abs", "", "I", 1, E, 0.5, 0.95, 2.5, None, "", "B"),
    ("crunch", "Crunch a corpo libero", "core_flexion", "bodyweight", "abs", "", "I", 1, BW, 0.35, 0.6, 2.5, 0.3, "neck", "B"),
    ("reverse_crunch", "Crunch inverso", "core_flexion", "bench", "abs", "obliques", "I", 1, BW, 0.4, 0.75, 2.5, 0.3, "", "B"),
]


def entry(row):
    (ident, name, pattern, equipment, primary, secondary, mech, difficulty, load, fatigue, stimulus,
     increment, fraction, contra, lat) = row
    item = {
        "id": ident,
        "nameKey": f"exercise.{ident}",
        "name": name,
        "pattern": pattern,
        "loadType": load,
        "equipment": equipment.split(),
        "primaryMuscles": primary.split(),
        "secondaryMuscles": secondary.split(),
        "mechanics": {"C": "compound", "I": "isolation"}[mech],
        "laterality": {"B": "bilateral", "U": "unilateral"}[lat],
        "difficulty": difficulty,
        "fatigueScore": fatigue,
        "stimulusScore": stimulus,
        "loadIncrementKg": increment,
        "contraindicatedAreas": contra.split(),
    }
    if fraction is not None:
        item["bodyweightFraction"] = fraction
    return item


def validate(items):
    errors = []
    ids = set()
    for it in items:
        i = it["id"]
        if i in ids:
            errors.append(f"{i}: id duplicato")
        ids.add(i)
        if it["pattern"] not in PATTERNS:
            errors.append(f"{i}: schema {it['pattern']}")
        for m in it["primaryMuscles"] + it["secondaryMuscles"]:
            if m not in MUSCLES:
                errors.append(f"{i}: muscolo {m}")
        if not it["primaryMuscles"]:
            errors.append(f"{i}: nessun muscolo primario")
        if set(it["primaryMuscles"]) & set(it["secondaryMuscles"]):
            errors.append(f"{i}: muscolo primario e secondario insieme")
        for e in it["equipment"]:
            if e not in EQUIPMENT:
                errors.append(f"{i}: attrezzatura {e}")
        for a in it["contraindicatedAreas"]:
            if a not in AREAS:
                errors.append(f"{i}: area {a}")
        if it["loadType"] in ("bodyweight", "assisted") and "bodyweightFraction" not in it:
            errors.append(f"{i}: manca bodyweightFraction")
        if it["loadType"] == "timed" and it["loadIncrementKg"] != 0:
            errors.append(f"{i}: un esercizio a tempo non ha incremento di carico")
        if not 0.3 <= it["fatigueScore"] <= 1.3 or not 0.6 <= it["stimulusScore"] <= 1.2:
            errors.append(f"{i}: fatica o stimolo fuori scala")
        if it["difficulty"] not in (1, 2, 3):
            errors.append(f"{i}: difficoltà")
    covered = {m for it in items for m in it["primaryMuscles"]}
    if covered != MUSCLES:
        errors.append(f"muscoli senza esercizi primari: {sorted(MUSCLES - covered)}")
    return errors


def render():
    items = sorted((entry(r) for r in TABLE), key=lambda x: x["id"])
    errors = validate(items)
    if errors:
        sys.exit("Catalogo non valido:\n" + "\n".join(errors))
    return json.dumps({"schemaVersion": 2, "exercises": items}, ensure_ascii=False, indent=1) + "\n"


def main():
    text = render()
    if "--check" in sys.argv:
        if OUTPUT.read_text(encoding="utf-8") != text:
            sys.exit("exercises.json non è aggiornato: esegui tools/catalog/generate_catalog.py")
        print(f"ok: catalogo aggiornato ({text.count('\"id\"')} esercizi)")
        return
    OUTPUT.write_text(text, encoding="utf-8")
    print(f"scritto {OUTPUT.relative_to(ROOT)} ({len(TABLE)} esercizi)")


if __name__ == "__main__":
    main()
