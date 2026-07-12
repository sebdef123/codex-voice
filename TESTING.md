# Validation d'acceptation

Ce protocole verifie le comportement qui ne peut pas etre valide sans ecouter l'app.

## Preparation

1. Quitter l'ancienne application `Codex Voice` afin d'eviter une double lecture.
2. Lancer `Codex Voice 2.app`.
3. Ouvrir `Ouvrir le log audio` depuis le menu de l'app si une analyse est necessaire.

Les evenements sont ecrits dans:

```text
~/Library/Logs/Codex Voice 2/voice-events.jsonl
```

Le premier evenement de chaque lancement est `app_started`; il indique la version, le moteur et la voix Voxtral selectionnes.

Le journal du serveur, lorsqu'il est lance par Codex Voice 2, est ici:

```text
~/Library/Logs/Codex Voice 2/voxtral-server.log
```

Par defaut, `voice-events.jsonl` ne contient pas le texte lu. Activer `Inclure le texte lu dans les logs de diagnostic` uniquement pour investiguer un cas precis. Verifier ensuite que les nouveaux evenements incluent les champs `raw`, `rawText`, `preparedText` ou `spoken`, puis utiliser `Effacer les logs audio` a la fin du test si le contenu est sensible.

## macOS TTS

1. Verifier que `Moteur > macOS TTS` est selectionne.
2. Faire produire a Codex une courte reponse, puis une reponse plus longue.
3. Pendant la lecture longue, presser Option droite et verifier l'arret immediat.
4. Utiliser les fleches gauche et droite pour relire un bloc precedent et le bloc suivant.

Attendus: voix macOS choisie, dictionnaire de prononciation actif seulement ici, `tts_requested`, `tts_first_audio`, puis soit `tts_finished`, soit `tts_interrupted` dans le log.

## Voxtral Streaming

1. Choisir `Moteur > Voxtral Streaming`.
2. Attendre que le statut passe de `Preparation Voxtral...` a `Surveillance active`.
3. Dans `Voix`, garder `French female (FR)` pour le premier essai.
4. Faire produire une reponse courte, puis une reponse longue.
5. Pendant la reponse longue, presser Option droite. Refaire un essai en envoyant une nouvelle demande Codex pendant la lecture.
6. Changer vers une voix anglaise puis verifier qu'un texte anglais est lu par la voix choisie.

Attendus: pas de voix macOS en secours; `tts_first_audio`, `streamFirstChunkDelaySeconds`, `streamPlaybackStartDelaySeconds`, `streamChunkCount`, `streamSegmentCount`, ressources serveur et memoire MLX dans l'evenement `tts_finished`. Les longues reponses sont segmentees par phrases tout en restant dans un seul flux. Les annulations doivent etre loguees avec `interruptionReason` et ne doivent jamais etre suivies d'une fin appartenant a la requete annulee.

## Cycle de ressources

1. Si Codex Voice 2 a demarre Voxtral lui-meme, revenir a `Moteur > macOS TTS` apres une lecture.
2. Verifier que le serveur est libere et que macOS TTS continue de fonctionner.
3. Revenir sur Voxtral Streaming et verifier le redemarrage propre puis une nouvelle lecture.

Si Local Voice Lab possede deja le serveur, Codex Voice 2 s'y attache: le retour a macOS ne doit pas couper le serveur du Lab.
