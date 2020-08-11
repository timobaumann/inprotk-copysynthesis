#!/usr/bin/perl

use strict;
use warnings;

#- wir brauchen etwas, mit dem wir das ganze Korpus einlesen (also alle TextGrids, jeweils mit den relevanten Spuren)
#	- Subcorpora sollten unterschieden werden können (Beispiel: mittlere Utterance-Länge nach Sub-Corpus)
#- wir wollen prüfen können, ob alle Wörter im Korpus im Lexikon sind, ggfs. dem Lexikon hinzufügen
#	- umgekehrt: aus dem Korpus das Lexikon generieren, vgl. Scripts/word-extract.pl
#- wir wollen die Häufigkeiten von Wort-tokens wissen 
#- wir wollen die Häufigkeiten der Aussprachen von Wort-Tokens wissen
#- wir wollen wissen, welche unterschiedlichen Wörter gleich ausgesprochen werden (die sollten am besten weg)
# 
# wohl eher im Lexikon:
#- finde verdächtig ähnlich geschriebene Wörter (groß/klein?)

package Corpus;

return 1;
