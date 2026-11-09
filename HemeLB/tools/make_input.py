#!/usr/bin/env python3
"""
make_input.py -- fabrique une variante du input.xml HemeLB (sans toucher a l'original)

Usage :
    python3 make_input.py ORIGINAL.xml SORTIE.xml [options]

Options :
    --steps N           change le nombre de pas (UNIQUEMENT pour les tests rapides)
    --no-monitoring     supprime la section <monitoring> (test "effet du monitoring de stabilite")
    --output-factor F   multiplie la "period" de chaque <propertyoutput> par F :
                          F = 0.1 -> on ecrit 10x PLUS souvent
                          F = 10  -> on ecrit 10x MOINS souvent
    --no-output         supprime la section <properties> (aucune ecriture de resultats)

Pourquoi des remplacements de texte (re) et pas un parseur XML ?
    Les input.xml de HemeLB contiennent des commentaires et des bouts de texte
    bizarres ; les reecrire avec un parseur ferait perdre ces commentaires.
    Ici on ne modifie QUE ce qui est demande, le reste du fichier est identique.
"""
import argparse
import re
import sys


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("dst")
    ap.add_argument("--steps", type=int, default=None)
    ap.add_argument("--no-monitoring", action="store_true")
    ap.add_argument("--output-factor", type=float, default=None)
    ap.add_argument("--no-output", action="store_true")
    a = ap.parse_args()

    text = open(a.src).read()
    changes = []

    if a.steps is not None:
        # <steps units="lattice" value="4500"/>
        text, n = re.subn(r'(<steps\b[^>]*\bvalue=")(\d+)(")',
                          lambda m: m.group(1) + str(a.steps) + m.group(3), text)
        changes.append(f"steps -> {a.steps} ({n} remplacement)")

    if a.no_monitoring:
        text, n = re.subn(r"<monitoring>.*?</monitoring>", "<!-- monitoring supprime (test T4) -->",
                          text, flags=re.S)
        changes.append(f"monitoring supprime ({n})")

    if a.output_factor is not None:
        def scale(m):
            old = int(m.group(2))
            new = max(1, int(round(old * a.output_factor)))
            changes.append(f"period {old} -> {new}")
            return m.group(1) + str(new) + m.group(3)
        # uniquement l'attribut period="..." des <propertyoutput ...>
        text = re.sub(r'(<propertyoutput\b[^>]*\bperiod=")(\d+)(")', scale, text)

    if a.no_output:
        text, n = re.subn(r"<properties>.*?</properties>", "<!-- properties supprimees (test T4) -->",
                          text, flags=re.S)
        changes.append(f"properties supprimees ({n})")

    with open(a.dst, "w") as f:
        f.write(text)
    print("make_input:", a.dst, "|", "; ".join(changes) if changes else "copie identique")


if __name__ == "__main__":
    sys.exit(main())
