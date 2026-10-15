-- =====================================================================
--  TP3 - Scenario de test (9 cas)
--  A executer en root, une fois 01, 03 et 02 charges :
--      Get-Content -Raw .\04-tests.sql | mysql -u root -p mediatheque -t
--
--  Le script choisit lui-meme ses cobayes (aucun id en dur, sauf T4 et T7
--  qui l'imposent) et REMET LA BASE EN ETAT a la fin : il se rejoue a l'infini.
--
--  Les cas qui DOIVENT echouer sont en commentaire ("-- CALL ..."), avec
--  le message d'erreur juste dessous. Pour les voir s'executer vraiment :
--      (Get-Content -Raw .\04-tests.sql) -replace '(?m)^-- (CALL )','$1' |
--          mysql -u root -p mediatheque --force -t 2>&1 | Tee-Object .\sortie-tests-tp3.txt
-- =====================================================================

USE mediatheque;

-- ---------------------------------------------------------------------
-- 0. Etat de depart (pour le nettoyage final)
-- ---------------------------------------------------------------------
SET @emp0 = (SELECT COALESCE(MAX(id), 0) FROM emprunt);
SET @pen0 = (SELECT COALESCE(MAX(id), 0) FROM penalite);
SET @jou0 = (SELECT COALESCE(MAX(id), 0) FROM journal_action);

-- ---------------------------------------------------------------------
-- 1. Les cobayes, choisis par la base
-- ---------------------------------------------------------------------
-- huit exemplaires disponibles et en service
SET @c1 = (SELECT code_barre FROM exemplaire WHERE disponible = 1 AND etat <> 'hors_service' ORDER BY id LIMIT 1 OFFSET 0);
SET @c2 = (SELECT code_barre FROM exemplaire WHERE disponible = 1 AND etat <> 'hors_service' ORDER BY id LIMIT 1 OFFSET 1);
SET @c3 = (SELECT code_barre FROM exemplaire WHERE disponible = 1 AND etat <> 'hors_service' ORDER BY id LIMIT 1 OFFSET 2);
SET @c4 = (SELECT code_barre FROM exemplaire WHERE disponible = 1 AND etat <> 'hors_service' ORDER BY id LIMIT 1 OFFSET 3);
SET @c5 = (SELECT code_barre FROM exemplaire WHERE disponible = 1 AND etat <> 'hors_service' ORDER BY id LIMIT 1 OFFSET 4);
SET @c6 = (SELECT code_barre FROM exemplaire WHERE disponible = 1 AND etat <> 'hors_service' ORDER BY id LIMIT 1 OFFSET 5);
SET @c7 = (SELECT code_barre FROM exemplaire WHERE disponible = 1 AND etat <> 'hors_service' ORDER BY id LIMIT 1 OFFSET 6);
SET @id_libre = (SELECT id FROM exemplaire WHERE disponible = 1 AND etat <> 'hors_service' ORDER BY id LIMIT 1 OFFSET 7);

-- quatre adherents actifs, sans emprunt ni penalite
SET @adh1 = (SELECT a.id FROM adherent a WHERE a.actif = 1 AND f_nb_emprunts_en_cours(a.id) = 0 AND f_penalites_dues(a.id) = 0 ORDER BY a.id LIMIT 1 OFFSET 0);
SET @adh2 = (SELECT a.id FROM adherent a WHERE a.actif = 1 AND f_nb_emprunts_en_cours(a.id) = 0 AND f_penalites_dues(a.id) = 0 ORDER BY a.id LIMIT 1 OFFSET 1);
SET @adh3 = (SELECT a.id FROM adherent a WHERE a.actif = 1 AND f_nb_emprunts_en_cours(a.id) = 0 AND f_penalites_dues(a.id) = 0 ORDER BY a.id LIMIT 1 OFFSET 2);
SET @adh4 = (SELECT a.id FROM adherent a WHERE a.actif = 1 AND f_nb_emprunts_en_cours(a.id) = 0 AND f_penalites_dues(a.id) = 0 ORDER BY a.id LIMIT 1 OFFSET 3);

-- un adherent inactif : un vrai s'il existe, sinon adh4 est desactive le
-- temps des tests (il est reactive au nettoyage)
SET @inactif   = (SELECT id FROM adherent WHERE actif = 0 ORDER BY id LIMIT 1);
SET @adh_temp1 = IF(@inactif IS NULL, @adh4, NULL);
UPDATE adherent SET actif = 0 WHERE id = @adh_temp1;
SET @inactif   = COALESCE(@inactif, @adh_temp1);

-- un adherent qui doit plus de 10 EUR : un vrai s'il existe, sinon on
-- fabrique une dette de test pour adh3 (supprimee au nettoyage)
SET @mauvais_payeur = (SELECT adherent_id FROM penalite WHERE payee = 0 GROUP BY adherent_id HAVING SUM(montant) > 10 LIMIT 1);
SET @adh_temp2      = IF(@mauvais_payeur IS NULL, @adh3, NULL);
INSERT INTO penalite (adherent_id, emprunt_id, montant, motif, date_creation, payee)
SELECT @adh_temp2, NULL, 10.40, 'Penalite de test', CURDATE(), 0 FROM DUAL WHERE @adh_temp2 IS NOT NULL;
SET @mauvais_payeur = COALESCE(@mauvais_payeur, @adh_temp2);

-- un emprunt en retard
SET @code_retard = (SELECT ex.code_barre
                      FROM emprunt em JOIN exemplaire ex ON ex.id = em.exemplaire_id
                     WHERE em.date_retour_reelle IS NULL AND em.date_retour_prevue < CURDATE()
                     ORDER BY em.date_retour_prevue LIMIT 1);
SET @emprunt_retard = (SELECT em.id
                         FROM emprunt em JOIN exemplaire ex ON ex.id = em.exemplaire_id
                        WHERE ex.code_barre = @code_retard AND em.date_retour_reelle IS NULL);

-- Aucune de ces valeurs ne doit etre NULL
SELECT @c1 AS c1, @id_libre AS id_libre, @adh1 AS adh1, @adh2 AS adh2,
       @inactif AS inactif, @mauvais_payeur AS mauvais_payeur,
       @code_retard AS code_retard, @emprunt_retard AS emprunt_retard;

-- ---------------------------------------------------------------------
-- T1 - un emprunt normal : emprunt cree, @id renseigne, exemplaire
--      indisponible, une ligne dans journal_action
-- ---------------------------------------------------------------------
SELECT '--- T1 ---' AS test;
CALL p_emprunter(@c1, @adh1, @id);
SELECT @id AS id_emprunt_cree;
SELECT id, exemplaire_id, adherent_id, date_emprunt, date_retour_prevue FROM emprunt WHERE id = @id;
SELECT code_barre, disponible FROM exemplaire WHERE code_barre = @c1;      -- disponible = 0
SELECT operation, cle, auteur, details FROM journal_action ORDER BY id DESC LIMIT 3;

-- ---------------------------------------------------------------------
-- T2 - DOIT ECHOUER : le meme exemplaire, un autre adherent
-- ---------------------------------------------------------------------
SELECT '--- T2 (doit echouer, voir commentaire) ---' AS test;
-- CALL p_emprunter(@c1, @adh2, @id);
-- ERROR 1644 (45000): Exemplaire deja emprunte.

-- ---------------------------------------------------------------------
-- T3 - DOIT ECHOUER : adherent dont l'inscription est inactive
-- ---------------------------------------------------------------------
SELECT '--- T3 (doit echouer, voir commentaire) ---' AS test;
-- CALL p_emprunter(@c2, @inactif, @id);
-- ERROR 1644 (45000): Inscription inactive : emprunt impossible.

-- ---------------------------------------------------------------------
-- T4 - DOIT ECHOUER : code-barres inconnu
-- ---------------------------------------------------------------------
SELECT '--- T4 (doit echouer, voir commentaire) ---' AS test;
-- CALL p_emprunter('MED-99999', 1, @id);
-- ERROR 1644 (45000): Code-barres inconnu.

-- ---------------------------------------------------------------------
-- T5 - cinq emprunts pour adh2, puis un sixieme qui DOIT ECHOUER
-- ---------------------------------------------------------------------
SELECT '--- T5 ---' AS test;
CALL p_emprunter(@c2, @adh2, @id);
CALL p_emprunter(@c3, @adh2, @id);
CALL p_emprunter(@c4, @adh2, @id);
CALL p_emprunter(@c5, @adh2, @id);
CALL p_emprunter(@c6, @adh2, @id);
SELECT f_nb_emprunts_en_cours(@adh2) AS emprunts_en_cours;                 -- 5
-- CALL p_emprunter(@c7, @adh2, @id);
-- ERROR 1644 (45000): Quota atteint : 5 documents maximum.

-- ---------------------------------------------------------------------
-- T6 - DOIT ECHOUER : adherent qui doit plus de 10 EUR
--      (autre adherent que adh2, sinon le quota s'appliquerait en premier)
-- ---------------------------------------------------------------------
SELECT '--- T6 (doit echouer, voir commentaire) ---' AS test;
SELECT @mauvais_payeur AS mauvais_payeur, f_penalites_dues(@mauvais_payeur) AS penalites_dues;
-- CALL p_emprunter(@c7, @mauvais_payeur, @id);
-- ERROR 1644 (45000): Penalites impayees superieures a 10 euros.

-- ---------------------------------------------------------------------
-- T7 - INSERT direct, sans passer par la procedure : le trigger fournit
--      quand meme la date du jour, le retour a +14 jours et l'exemplaire
--      indisponible
-- ---------------------------------------------------------------------
SELECT '--- T7 ---' AS test;
INSERT INTO emprunt (exemplaire_id, adherent_id, date_emprunt, date_retour_prevue)
VALUES (@id_libre, 2, NULL, NULL);
SELECT id, date_emprunt, date_retour_prevue,
       DATEDIFF(date_retour_prevue, date_emprunt) AS duree_jours
  FROM emprunt ORDER BY id DESC LIMIT 1;                                   -- 14 jours
SELECT id, disponible FROM exemplaire WHERE id = @id_libre;                -- 0

-- ---------------------------------------------------------------------
-- T8 - retour d'un emprunt en retard : emprunt clos, exemplaire
--      disponible, penalite au bon montant (jours x 0,20)
-- ---------------------------------------------------------------------
SELECT '--- T8 ---' AS test;
SELECT f_jours_de_retard(@emprunt_retard) AS jours_de_retard_avant;
CALL p_rendre(@code_retard);
SELECT code_barre, disponible FROM exemplaire WHERE code_barre = @code_retard;   -- 1
SELECT adherent_id, montant, motif FROM penalite ORDER BY id DESC LIMIT 1;
SELECT id, date_retour_reelle FROM emprunt WHERE id = @emprunt_retard;

-- ---------------------------------------------------------------------
-- T9 - DOIT ECHOUER : le meme code-barres une deuxieme fois
-- ---------------------------------------------------------------------
SELECT '--- T9 (doit echouer, voir commentaire) ---' AS test;
-- CALL p_rendre(@code_retard);
-- ERROR 1644 (45000): Aucun emprunt en cours pour ce code-barres.

-- ---------------------------------------------------------------------
-- Cas supplementaire : un retour dans les temps ne cree AUCUNE penalite
-- ---------------------------------------------------------------------
SELECT '--- Retour dans les temps ---' AS test;
SET @nb_pen = (SELECT COUNT(*) FROM penalite);
CALL p_rendre(@c1);                                                        -- montant_facture = 0.00
SELECT (SELECT COUNT(*) FROM penalite) - @nb_pen AS penalites_creees;      -- 0

-- ---------------------------------------------------------------------
-- Bilan d'un adherent : trois jeux de resultats
-- ---------------------------------------------------------------------
SELECT '--- p_bilan_adherent ---' AS test;
CALL p_bilan_adherent(@adh2);

-- ---------------------------------------------------------------------
-- Nettoyage : la base retrouve exactement son etat de depart
-- ---------------------------------------------------------------------
-- 1) liberer les exemplaires pris pendant les tests
UPDATE exemplaire SET disponible = 1
 WHERE id IN (SELECT exemplaire_id FROM emprunt WHERE id > @emp0);

-- 2) supprimer penalites, emprunts et traces crees par les tests
DELETE FROM penalite WHERE id > @pen0;
DELETE FROM emprunt  WHERE id > @emp0;

-- 3) remettre en cours l'emprunt en retard rendu en T8
--    (le trigger ne passe l'exemplaire a "indisponible" qu'a l'INSERT : a la main)
UPDATE emprunt SET date_retour_reelle = NULL WHERE id = @emprunt_retard;
UPDATE exemplaire SET disponible = 0 WHERE code_barre = @code_retard;

-- 4) reactiver l'adherent desactive pour le test T3, effacer le journal de test
UPDATE adherent SET actif = 1 WHERE id = @adh_temp1;
DELETE FROM journal_action WHERE id > @jou0;

SELECT 'Nettoyage termine.' AS resultat;
