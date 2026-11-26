# Erfolge für Steamworks

Aus `scripts/autoload/achievement_manager.gd` (LIST). In Steamworks unter *Stats & Achievements* genau mit diesen API-Namen anlegen. Die Reihenfolge entspricht der Anzeige im Spiel.

| API-Name | Titel (DE) | Beschreibung (DE) | Title (EN) | Description (EN) |
|---|---|---|---|---|
| ACH_FIRST_RACK | Erstes Rack | Stelle dein erstes Rack auf. | First Rack | Set up your first rack. |
| ACH_FIRST_SERVER | Es läuft! | Ein Server läuft mit Strom und Netz. | It's Alive! | A server runs with power and network. |
| ACH_FIRST_CUSTOMER | Erster Kunde | Vermiete ein Rack an einen Kunden. | First Customer | Rent out a rack to a customer. |
| ACH_CONTRACTS_5 | Vertragspartner | Habe fünf Verträge gleichzeitig laufen. | Contract Partner | Have five contracts running at once. |
| ACH_RACKS_10 | Serverraum | Betreibe zehn Racks gleichzeitig. | Server Room | Run ten racks at once. |
| ACH_RACKS_25 | Rechenzentrum | Betreibe 25 Racks gleichzeitig. | Data Center | Run 25 racks at once. |
| ACH_COMPUTE_1000 | Tausend Recheneinheiten | Erreiche 1.000 CU Rechenleistung. | A Thousand Units | Reach 1,000 CU of compute. |
| ACH_COMPUTE_10000 | Großrechner | Erreiche 10.000 CU Rechenleistung. | Mainframe | Reach 10,000 CU of compute. |
| ACH_MONEY_100K | Sechsstellig | Habe 100.000 $ auf dem Konto. | Six Figures | Have $100,000 in the bank. |
| ACH_MONEY_1M | Millionär | Habe 1.000.000 $ auf dem Konto. | Millionaire | Have $1,000,000 in the bank. |
| ACH_LEVEL_3 | Mittelstand | Erreiche Firmenstufe 3. | Mid-Sized Business | Reach company level 3. |
| ACH_LEVEL_5 | Etabliert | Erreiche Firmenstufe 5. | Established | Reach company level 5. |
| ACH_LEVEL_10 | Marktführer | Erreiche Firmenstufe 10. | Market Leader | Reach company level 10. |
| ACH_RESEARCH | Forschergeist | Erforsche deine erste Stufe. | Curious Mind | Research your first level. |
| ACH_REPUTATION_80 | Guter Ruf | Bring den Ruf deiner Firma auf 80. | Good Reputation | Raise your company's reputation to 80. |
| ACH_HALLE_NORD | Ab in den Norden | Kaufe Halle Nord. | Heading North | Buy Hall North. |
| ACH_DAY_30 | Ein Monat Betrieb | Halte dein Rechenzentrum 30 Tage am Laufen. | One Month Online | Keep your data center running for 30 days. |
| ACH_FIRE_OUT | Brandschutz | Lösche einen Brand im Rechenzentrum. | Fire Safety | Put out a fire in the data center. |
| ACH_TEAM | Teamarbeit | Spiele mit mindestens einem Mitspieler. | Teamwork | Play with at least one other player. |

19 Erfolge. Kommt ein neuer dazu, diese Tabelle neu erzeugen (Test `tests/launcher_release_check.gd` prüft, dass sie zur Liste passt).
