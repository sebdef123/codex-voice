# Changelog

## 1.0.3 - 2026-07-13

- La reserve audio initiale de Voxtral est reglable de 0,7 a 2,5 secondes depuis le menu.
- Le reglage s'applique a la lecture suivante sans redemarrage et reste memorise.
- La reserve choisie est ajoutee aux logs de chaque lecture Voxtral.
- Les chunks Voxtral passent de 0,4 a 0,8 seconde pour reduire le cout du decodage repete et les risques de micro-coupure.
- Le decoupage Voxtral passe de 650 a 1 000 caracteres et privilegie les frontieres de paragraphes puis de phrases.

## 1.0.2 - 2026-07-12

- Les lignes automatiques `Skill used:` et `Skill utilisée:` sont ignorees a la lecture.

## 1.0.1 - 2026-07-12

- Menus, statuts et alertes localises automatiquement en francais ou en anglais.
- L'anglais est utilise comme repli pour les autres langues systeme.

## 1.0.0 - 2026-07-12

- Lecture locale des reponses Codex avec macOS TTS ou Voxtral Streaming.
- Interruption immediate, relecture des blocs et selection de voix persistante.
- Dictionnaire macOS externe, cree au premier lancement, avec import et export.
- Logs de diagnostic prives par defaut, texte active uniquement sur demande.
- Serveur Voxtral local demarre a la demande puis libere lorsque macOS TTS est selectionne.
- Surveillance des transcripts renforcee contre les ecritures JSONL partielles et les sessions de sous-agents.
- Archive ZIP de transfert personnel avec preparation Voxtral optionnelle.
