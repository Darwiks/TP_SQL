-- =====================================================================
--  TP2 - Partie B : index
--  Prerequis : 03-volume.sql charge (environ 200 130 emprunts).
--  A executer en root, AVEC --force (certains DROP INDEX echouent la 1re fois,
--  et le dernier DROP INDEX DOIT echouer) :
--
--    Get-Content -Raw .\03-index.sql | mysql -u root -p mediatheque --force -t 2>&1 | Tee-Object -FilePath .\sortie-index.txt
--
--  Rejouable : l'etape 0 remet la table dans son etat sans index.
-- =====================================================================

USE mediatheque;

-- ---------------------------------------------------------------------
-- 0. Remise a zero (erreurs 1091 normales a la 1re execution : l'index
--    n'existe pas encore).
--    On supprime puis recree la cle etrangere : InnoDB lui recree son
--    index implicite sur adherent_id, que le composite avait remplace.
-- ---------------------------------------------------------------------
ALTER TABLE emprunt DROP FOREIGN KEY fk_emprunt_adherent;
DROP INDEX idx_emprunt_adherent_date  ON emprunt;
DROP INDEX idx_emprunt_date           ON emprunt;
DROP INDEX idx_emprunt_retour_reelle  ON emprunt;
ALTER TABLE emprunt ADD CONSTRAINT fk_emprunt_adherent
  FOREIGN KEY (adherent_id) REFERENCES adherent (id);
ANALYZE TABLE emprunt;

SELECT COUNT(*) AS emprunts_total FROM emprunt;

-- Taille AVANT index (consigne 10)
SELECT 'TAILLE AVANT' AS etape,
       ROUND(data_length/1024/1024,2)  AS donnees_mo,
       ROUND(index_length/1024/1024,2) AS index_mo
  FROM information_schema.tables
 WHERE table_schema='mediatheque' AND table_name='emprunt';

-- Index deja presents (ceux des cles etrangeres)
SELECT index_name, column_name, seq_in_index
  FROM information_schema.statistics
 WHERE table_schema='mediatheque' AND table_name='emprunt'
 ORDER BY index_name, seq_in_index;

-- ---------------------------------------------------------------------
-- 1. Consigne 5 : EXPLAIN AVANT (aucun index hors cles etrangeres)
-- ---------------------------------------------------------------------
SELECT '--- R1 AVANT ---' AS etape;
EXPLAIN SELECT * FROM emprunt WHERE date_emprunt = '2024-03-12';
SELECT COUNT(*) AS lignes_r1 FROM emprunt WHERE date_emprunt = '2024-03-12';

SELECT '--- R2 AVANT ---' AS etape;
EXPLAIN SELECT * FROM emprunt WHERE date_retour_reelle IS NULL;
SELECT COUNT(*) AS lignes_r2 FROM emprunt WHERE date_retour_reelle IS NULL;

SELECT '--- R3 AVANT ---' AS etape;
EXPLAIN SELECT id, date_emprunt FROM emprunt
 WHERE adherent_id = 12 AND date_emprunt >= '2025-01-01';
SELECT COUNT(*) AS lignes_r3 FROM emprunt
 WHERE adherent_id = 12 AND date_emprunt >= '2025-01-01';

-- Requete a reecrire (consigne 9) : etat AVANT index
SELECT '--- YEAR() AVANT INDEX ---' AS etape;
EXPLAIN SELECT COUNT(*) FROM emprunt WHERE YEAR(date_emprunt) = 2024;

-- ---------------------------------------------------------------------
-- 2. Consigne 6 : un index par requete, chacun justifie
-- ---------------------------------------------------------------------

-- R1 : filtre d'egalite sur date_emprunt ; une journee = quelques dizaines de
--      lignes sur 200 000, l'index est tres selectif.
CREATE INDEX idx_emprunt_date ON emprunt (date_emprunt);
ANALYZE TABLE emprunt;
SELECT '--- R1 APRES ---' AS etape;
EXPLAIN SELECT * FROM emprunt WHERE date_emprunt = '2024-03-12';

-- R2 : IS NULL sur date_retour_reelle ; presque tous les emprunts sont rendus,
--      donc tres peu de lignes NULL : l'index est tres selectif.
CREATE INDEX idx_emprunt_retour_reelle ON emprunt (date_retour_reelle);
ANALYZE TABLE emprunt;
SELECT '--- R2 APRES ---' AS etape;
EXPLAIN SELECT * FROM emprunt WHERE date_retour_reelle IS NULL;

-- R3 : egalite sur adherent_id PUIS plage sur date_emprunt. L'egalite doit venir
--      en premier, la plage en dernier : MySQL se positionne sur adherent_id = 12
--      puis parcourt la plage de dates dans l'ordre. Dans l'ordre inverse
--      (date_emprunt, adherent_id), la plage sur date_emprunt empecherait
--      d'utiliser adherent_id pour affiner. L'index contient aussi id (cle
--      primaire) et les 2 colonnes demandees : il COUVRE la requete.
CREATE INDEX idx_emprunt_adherent_date ON emprunt (adherent_id, date_emprunt);
ANALYZE TABLE emprunt;
SELECT '--- R3 APRES ---' AS etape;
EXPLAIN SELECT id, date_emprunt FROM emprunt
 WHERE adherent_id = 12 AND date_emprunt >= '2025-01-01';

-- (Pas d'index sur exemplaire_id seul : la cle etrangere en a deja un.)

-- ---------------------------------------------------------------------
-- 3. Consigne 7 : le prefixe gauche
-- ---------------------------------------------------------------------
SELECT '--- PREFIXE GAUCHE ---' AS etape;
-- adherent_id est la 1re colonne du composite : il peut servir.
EXPLAIN SELECT id FROM emprunt WHERE adherent_id = 12;
-- date_emprunt est la 2e colonne, la 1re n'est pas filtree : le composite ne
-- peut pas servir ; MySQL prend idx_emprunt_date ou lit toute la table.
EXPLAIN SELECT id FROM emprunt WHERE date_emprunt >= '2025-01-01';

-- ---------------------------------------------------------------------
-- 4. Consigne 8 : l'index couvrant
-- ---------------------------------------------------------------------
SELECT '--- INDEX COUVRANT ---' AS etape;
-- Toutes les colonnes demandees sont dans l'index : Extra = "Using index".
EXPLAIN SELECT adherent_id, date_emprunt FROM emprunt WHERE adherent_id = 12;
-- exemplaire_id n'est pas dans l'index : "Using index" disparait, MySQL doit
-- lire la ligne complete dans la table pour chaque ligne trouvee.
EXPLAIN SELECT adherent_id, date_emprunt, exemplaire_id FROM emprunt WHERE adherent_id = 12;

-- ---------------------------------------------------------------------
-- 5. Consigne 9 : la requete a reecrire
-- ---------------------------------------------------------------------
SELECT '--- YEAR() ---' AS etape;
-- D'origine : YEAR() est applique a la colonne, l'index ne peut pas servir.
EXPLAIN SELECT COUNT(*) FROM emprunt WHERE YEAR(date_emprunt) = 2024;
SELECT COUNT(*) AS nb_year FROM emprunt WHERE YEAR(date_emprunt) = 2024;

-- Reecrite : comparaison directe sur la colonne, l'index sert.
EXPLAIN SELECT COUNT(*) FROM emprunt
 WHERE date_emprunt >= '2024-01-01' AND date_emprunt < '2025-01-01';
SELECT COUNT(*) AS nb_reecrite FROM emprunt
 WHERE date_emprunt >= '2024-01-01' AND date_emprunt < '2025-01-01';
-- Les deux COUNT(*) doivent etre identiques.

-- ---------------------------------------------------------------------
-- 6. Consigne 10 : le prix des index
-- ---------------------------------------------------------------------
ANALYZE TABLE emprunt;
SELECT 'TAILLE APRES' AS etape,
       ROUND(data_length/1024/1024,2)  AS donnees_mo,
       ROUND(index_length/1024/1024,2) AS index_mo
  FROM information_schema.tables
 WHERE table_schema='mediatheque' AND table_name='emprunt';

-- Index presents apres creation (le composite a-t-il remplace celui de la FK ?)
SELECT index_name, column_name, seq_in_index
  FROM information_schema.statistics
 WHERE table_schema='mediatheque' AND table_name='emprunt'
 ORDER BY index_name, seq_in_index;

-- ---------------------------------------------------------------------
-- 7. Bonus 12 : la vue lente
-- ---------------------------------------------------------------------
SELECT '--- BONUS 12 : v_retard ---' AS etape;
EXPLAIN SELECT * FROM v_retard;

-- ---------------------------------------------------------------------
-- 8. Bonus 11 : l'index qui resiste (A LAISSER EN DERNIER)
--    Attendu : ERROR 1553 (HY000) - index necessaire a une cle etrangere.
--    InnoDB exige un index sur adherent_id pour fk_emprunt_adherent ; le
--    composite a remplace l'index implicite de la cle etrangere, c'est
--    maintenant lui qui garantit la contrainte.
-- ---------------------------------------------------------------------
SELECT '--- BONUS 11 : DROP INDEX (doit echouer) ---' AS etape;
DROP INDEX idx_emprunt_adherent_date ON emprunt;
