-- Vytvořil: Michal Kaňkovský, Valentyn Vorobec

-- Byl lehce pozměněn původní ERD. Přidáno ID do Předpisu aby bylo splněno zadání.

-- Dropovani
DROP TABLE osoba CASCADE CONSTRAINTS;
DROP TABLE pacient CASCADE CONSTRAINTS;
DROP TABLE lekar CASCADE CONSTRAINTS;
DROP TABLE leky CASCADE CONSTRAINTS;
DROP TABLE oddeleni CASCADE CONSTRAINTS;
DROP TABLE vybaveni CASCADE CONSTRAINTS;
DROP TABLE vysetreni CASCADE CONSTRAINTS;
DROP TABLE navstevuje CASCADE CONSTRAINTS;
DROP TABLE predpis CASCADE CONSTRAINTS;
DROP SEQUENCE SEQ_predpis;

-- Auto-inkrementujici ID pro predpisy
CREATE SEQUENCE SEQ_predpis
   MINVALUE 1
   START WITH 1
   INCREMENT BY 1
   CACHE 10;

CREATE TABLE oddeleni(
   zkratka VARCHAR(3) NOT NULL,
   mistnost VARCHAR(32) NOT NULL,
   -- RC_vedouci je po vytvoreni tabulky lekar pres ALTER nastaveno jako FK z tabulky lekar
   RC_vedouci VARCHAR(11),

   CONSTRAINT PK_zkratka PRIMARY KEY (zkratka)
);

-- Tabulka osoba dedi z ni tabulky pacient a lekar. Jsou propojy Rodným Číslem a to je kontrolováné regulárním výrazem
CREATE TABLE osoba(
   RC VARCHAR(11) NOT NULL,
   jmeno VARCHAR(16) NOT NULL,
   prijmeni VARCHAR(16) NOT NULL,
   datum_narozeni DATE NOT NULL,
   bydliste VARCHAR(64) NOT NULL,
   pohlavi VARCHAR(1) NOT NULL,
   mobil NUMBER(9),
   email VARCHAR(32),
   CONSTRAINT CK_RC CHECK (REGEXP_LIKE(RC, '^[0-9]{2}(0[1-9]|1[0-2]|5[1-9]|6[0-2])(0[1-9]|1[0-9]|2[0-9]|3[0-1])\/[0-9]{4}$')),
   CONSTRAINT CK_email CHECK (REGEXP_LIKE(email, '^\S+@\S+\.\S+$')),
   CONSTRAINT PK_RC PRIMARY KEY (RC)
);

-- specializace tabulky osoba
CREATE TABLE pacient(
   RC VARCHAR(11) NOT NULL,
   c_pojistovny NUMBER(10),
   zdravotni_popis VARCHAR(4000), 

   CONSTRAINT FK_RC FOREIGN KEY (RC) REFERENCES osoba,
   CONSTRAINT PK_RC_pacient PRIMARY KEY (RC)
);

-- specializace tabulky osoba
CREATE TABLE lekar(
   RC VARCHAR(11) NOT NULL,
   specializace VARCHAR(32) NOT NULL,
   telefon NUMBER(9) NOT NULL,
   oddeleni_zkratka VARCHAR(3) NOT NULL,

   CONSTRAINT FK_oddeleni_lekar FOREIGN KEY (oddeleni_zkratka) REFERENCES oddeleni,
   CONSTRAINT FK_RC_lekar FOREIGN KEY (RC) REFERENCES osoba,
   CONSTRAINT PK_RC_lekar PRIMARY KEY (RC)
);

ALTER TABLE oddeleni ADD CONSTRAINT FK_RC_vedouci_oddeleni FOREIGN KEY (RC_vedouci) REFERENCES lekar;

CREATE TABLE navstevuje(
   RC_lekar VARCHAR(11) NOT NULL,
   RC_pacient VARCHAR(11) NOT NULL,

   CONSTRAINT FK_RC_pacient_navstevuje FOREIGN KEY (RC_pacient) REFERENCES pacient,
   CONSTRAINT FK_RC_lekar_navstevuje FOREIGN KEY (RC_lekar) REFERENCES lekar,
   CONSTRAINT PK_navstevuje PRIMARY KEY (RC_lekar, RC_pacient)
);

CREATE TABLE vybaveni(
   seriove_cislo NUMBER(8) NOT NULL,
   nazev VARCHAR(32) NOT NULL,
   oddeleni_zkratka VARCHAR(3),
   
   CONSTRAINT PK_seriove_cislo PRIMARY KEY (seriove_cislo)
);

CREATE TABLE leky(
   lek_ID VARCHAR(11) NOT NULL,
   nazev VARCHAR(32) NOT NULL,
   popis VARCHAR(4000) NOT NULL,

   CONSTRAINT PK_lek_ID PRIMARY KEY (lek_ID)
);

CREATE TABLE vysetreni(
   RC_pacient VARCHAR(11) NOT NULL,
   RC_lekar VARCHAR(11) NOT NULL,
   datum DATE NOT NULL,
   popis VARCHAR(4000),

   CONSTRAINT FK_RC_pacient_vysetreni FOREIGN KEY (RC_pacient) REFERENCES pacient,
   CONSTRAINT FK_RC_lekar_vysetreni FOREIGN KEY (RC_lekar) REFERENCES lekar,
   CONSTRAINT PK_vysetreni PRIMARY KEY (RC_pacient, RC_lekar, datum)
);

CREATE TABLE predpis(
   ID_predpis NUMBER(12) DEFAULT SEQ_predpis.nextval NOT NULL,
   RC_pacient VARCHAR(11) NOT NULL,
   RC_lekar VARCHAR(11) NOT NULL,
   lek_ID VARCHAR(11) NOT NULL,
   datum_vystaveni DATE NOT NULL,
   datum_platnosti DATE NOT NULL,
   popis VARCHAR(4000),

   CONSTRAINT FK_RC_pacient_predpis FOREIGN KEY (RC_pacient) REFERENCES pacient,
   CONSTRAINT FK_RC_lekar_predpis FOREIGN KEY (RC_lekar) REFERENCES lekar,
   CONSTRAINT FK_lek_ID_predpis FOREIGN KEY (lek_ID) REFERENCES leky,
   CONSTRAINT PK_predpis PRIMARY KEY (ID_predpis, RC_pacient, RC_lekar, lek_ID)
);

CREATE OR REPLACE TRIGGER trg_prevent_duplicate_vysetreni_pacient
BEFORE INSERT ON vysetreni
FOR EACH ROW
DECLARE
    v_count NUMBER;
BEGIN
    -- Zjistíme, jestli existuje vyšetření se stejným časem
    SELECT COUNT(*) INTO v_count
    FROM vysetreni
    WHERE RC_pacient = :NEW.RC_pacient AND datum = :NEW.datum;
    
    -- Pokud existuje vyšetření se stejným časem, tak vyvoláme chybu
    IF v_count > 0 THEN
        RAISE_APPLICATION_ERROR(-20001, 'Nelze vytvořit nové vyšetření s tímto časem, pacient již má ve stejný čas vyšetření.');
    END IF;
END;
/

-- podobný trigger, není to v jednou triggeru, aby mohla být vypsán důvod neúspěchu
CREATE OR REPLACE TRIGGER trg_prevent_duplicate_vysetreni_lekar
BEFORE INSERT ON vysetreni
FOR EACH ROW
DECLARE
    v_count NUMBER;
BEGIN
    -- Zjistíme, jestli existuje vyšetření se stejným časem
    SELECT COUNT(*) INTO v_count
    FROM vysetreni
    WHERE RC_lekar = :NEW.RC_lekar AND datum = :NEW.datum;
    
    -- Pokud existuje vyšetření se stejným časem, tak vyvoláme chybu
    IF v_count > 0 THEN
        RAISE_APPLICATION_ERROR(-20001, 'Nelze vytvořit nové vyšetření s tímto časem, lékař již má ve stejný čas vyšetření');
    END IF;
END;
/

CREATE OR REPLACE PROCEDURE vytvor_osobu(
   n_RC IN VARCHAR,
   n_jmeno IN VARCHAR,
   n_prijmeni IN VARCHAR,
   n_datum_narozeni IN DATE,
   n_bydliste IN VARCHAR,
   n_pohlavi IN VARCHAR,
   n_mobil IN NUMBER,
   n_email IN VARCHAR
)
IS
   v_error_code NUMBER := 0;
BEGIN 
   -- Ověření, zda email již neexistuje v databázi
   SELECT COUNT(*) INTO v_error_code FROM osoba WHERE email = n_email; -- Použití parametru email namísto v_email
   IF v_error_code > 0 THEN
      RAISE_APPLICATION_ERROR(-20001, 'Email: ' || n_email || ' již existuje v databázi.');  
   END IF;

   -- Vložení nového pacienta do databáze
   INSERT INTO osoba (RC, jmeno, prijmeni, datum_narozeni, bydliste, pohlavi, mobil, email) -- Přidání chybějícího sloupce prijmeni
   VALUES (n_RC, n_jmeno, n_prijmeni, n_datum_narozeni, n_bydliste, n_pohlavi, n_mobil, n_email);
               
   COMMIT;
END;
/

-- procedura pouzivajici kurzor k vypsani vsech leku, jejichz popis obsahuje zadany string
CREATE OR REPLACE PROCEDURE vyhledat_lek(
   v_popis IN VARCHAR
)
IS
   v_error_code NUMBER := 0;
BEGIN 

   DECLARE 
   c_lek_ID leky.lek_ID%type; 
   c_nazev leky.nazev%type; 
   c_popis leky.popis%type; 
   CURSOR c_leky is 
      SELECT lek_ID, nazev, popis FROM leky; 

   BEGIN 
      OPEN c_leky; 
      LOOP 
      FETCH c_leky into c_lek_ID, c_nazev, c_popis; 
         EXIT WHEN c_leky%notfound; 
         IF c_popis LIKE '%' || v_popis || '%' THEN
            dbms_output.put_line(c_lek_ID || ' ' || c_nazev || ' ' || c_popis); 
         END IF;
      END LOOP; 
      CLOSE c_leky; 
   END;
   COMMIT;
END;
/

-- Vlozeni testovacich dat
INSERT INTO osoba (RC, jmeno, prijmeni, datum_narozeni, bydliste, pohlavi, mobil, email)
VALUES ('951211/1234', 'Jan', 'Novák', TO_DATE('1995-12-31', 'YYYY-MM-DD'), 'Praha 1', 'M', 123456789, 'jan.novak@email.com');

INSERT INTO osoba (RC, jmeno, prijmeni, datum_narozeni, bydliste, pohlavi, mobil, email)
VALUES ('800101/1234', 'Honza', 'Hricák', TO_DATE('1999-02-12', 'YYYY-MM-DD'), 'Třebíč 1', 'M', 987654321, 'honza.hric@email.com');

INSERT INTO osoba (RC, jmeno, prijmeni, datum_narozeni, bydliste, pohlavi, mobil, email)
VALUES ('020202/0002', 'Valentyn', 'Vorobec', TO_DATE('1876-07-11', 'YYYY-MM-DD'), 'Třebíč 1', 'M', 760113212, 'valen.tyn@email.com');

INSERT INTO osoba (RC, jmeno, prijmeni, datum_narozeni, bydliste, pohlavi, mobil, email)
VALUES ('010101/0001', 'Alfonz', 'Bílý', TO_DATE('2001-01-01', 'YYYY-MM-DD'), 'Praha', 'M', 123213123, 'Alfonz.BILYvak@email.com');

INSERT INTO osoba (RC, jmeno, prijmeni, datum_narozeni, bydliste, pohlavi, mobil, email)
VALUES ('090101/0001', 'Sasha', 'Ginger', TO_DATE('2000-01-01', 'YYYY-MM-DD'), 'Praha', '?', 123213123, 'SASHA.vak@email.com');

INSERT INTO pacient (RC, c_pojistovny, zdravotni_popis)
VALUES ('090101/0001', 1234511890, 'Na práhu smrti.');

INSERT INTO pacient (RC, c_pojistovny, zdravotni_popis)
VALUES ('951211/1234', 1234567890, 'Bez zdravotních problémů.');

INSERT INTO pacient (RC, c_pojistovny, zdravotni_popis)
VALUES ('010101/0001', 1234567890, 'Bez zdravotních problémů');

INSERT INTO oddeleni (zkratka, mistnost, RC_vedouci)
VALUES ('KAR', '123', NULL);

INSERT INTO lekar (RC, specializace, telefon, oddeleni_zkratka)
VALUES ('800101/1234', 'Kardiologie', 153456789, 'KAR');

INSERT INTO lekar (RC, specializace, telefon, oddeleni_zkratka)
VALUES ('020202/0002', 'Kardiochirurg', 987654321, 'KAR');

INSERT INTO navstevuje (RC_lekar, RC_pacient)
VALUES ('800101/1234', '951211/1234');

INSERT INTO navstevuje (RC_lekar, RC_pacient)
VALUES ('020202/0002', '010101/0001');

INSERT INTO vybaveni (seriove_cislo, nazev, oddeleni_zkratka)
VALUES (12345678, 'Stetoskop', 'KAR');

INSERT INTO vybaveni (seriove_cislo, nazev, oddeleni_zkratka)
VALUES (89675423, 'EKG přístroj', 'KAR');

INSERT INTO leky (lek_ID, nazev, popis)
VALUES (1, 'Aspirin', 'Lék proti bolesti a horečce.');

INSERT INTO leky (lek_ID, nazev, popis)
VALUES (2, 'Paralen', 'Na bolest a horečku');

INSERT INTO leky (lek_ID, nazev, popis)
VALUES (3, 'Milgama', 'Na zánět');

INSERT INTO vysetreni (RC_pacient, RC_lekar, datum, popis)
VALUES ('951211/1234', '800101/1234', TO_DATE('2023-03-26 12:00', 'YYYY-MM-DD HH24:MI'), 'Pravidelná kontrola srdce.');



INSERT INTO vysetreni (RC_pacient, RC_lekar, datum, popis)
VALUES ('090101/0001', '020202/0002', TO_DATE('2023-03-26 12:00', 'YYYY-MM-DD HH24:MI'), 'Operace srdce.');

INSERT INTO vysetreni (RC_pacient, RC_lekar, datum, popis)
VALUES ('090101/0001', '020202/0002', TO_DATE('2001-01-01 15:00', 'YYYY-MM-DD HH24:MI'), 'Operace kolena.');

INSERT INTO predpis (RC_pacient, RC_lekar, lek_ID, datum_vystaveni, datum_platnosti, popis)
VALUES ('951211/1234', '800101/1234', 1, TO_DATE('2023-03-26', 'YYYY-MM-DD'), TO_DATE('2023-04-26', 'YYYY-MM-DD'), 'Užívat 1 tabletku denně.');

INSERT INTO predpis (RC_pacient, RC_lekar, lek_ID, datum_vystaveni, datum_platnosti, popis)
VALUES ('010101/0001', '020202/0002', 1, TO_DATE('2022-01-01', 'YYYY-MM-DD'), TO_DATE('2022-02-01', 'YYYY-MM-DD'), 'Paralen na bolesti hlavy');


COMMIT;
SELECT * FROM osoba;
/*
-- Vypis testovacich dat
SELECT * FROM osoba;
-- Vypis pacientu
SELECT * FROM osoba NATURAL JOIN pacient;
-- Vypis lekaru
SELECT * FROM osoba NATURAL JOIN lekar;
SELECT * FROM leky;
SELECT * FROM oddeleni;
SELECT * FROM vybaveni;
SELECT * FROM vysetreni;
SELECT * FROM navstevuje;
SELECT * FROM predpis;
*/

-- Selecty se spojenim dvou tabulek
   -- Vypis pacientu
   SELECT * FROM osoba NATURAL JOIN pacient;
   -- Vypis lekaru
   SELECT * FROM osoba NATURAL JOIN lekar;



-- Select se spojenim tri tabulek. Vypise informace o vysetrenich
SELECT pacient.RC, lekar.RC, TO_CHAR(vysetreni.DATUM, 'DD-MON-YYYY HH24:MI'), vysetreni.popis
FROM vysetreni
JOIN pacient ON vysetreni.RC_pacient = pacient.RC
JOIN lekar ON vysetreni.RC_lekar = lekar.RC;

-- GROUP BY s agregacni funkci COUNT. Jine funkce v teto databazi nedavaji smysl
-- spocita zastoupeni jednotlivich pohlavi u pacientu
SELECT pohlavi, COUNT(*)
FROM pacient
NATURAL JOIN osoba
GROUP BY pohlavi;
-- spocita zastoupeni jednotlivich jmen u pacientu
SELECT jmeno, COUNT(*)
FROM pacient
NATURAL JOIN osoba
GROUP BY jmeno;

-- Vypise pacienta, ktery ma vysetreni a nema pohlavi "M" nebo "Z"
SELECT p.RC, o.jmeno, o.prijmeni
FROM pacient p
JOIN osoba o ON p.RC = o.RC
WHERE o.pohlavi <> 'Z' AND o.pohlavi <> 'M'
AND EXISTS (
   SELECT *
   FROM vysetreni v
   WHERE v.RC_pacient = p.RC
);

-- SELECT spolu s IN a vnorenym SELECT. Vypise pacienty, ktery meli v roce 2022 vysetreni.
SELECT *
FROM pacient
WHERE RC IN (
    SELECT RC_pacient
    FROM vysetreni
    WHERE vysetreni.datum BETWEEN TO_DATE('2022-01-01', 'YYYY-MM-DD') AND TO_DATE('2022-12-31', 'YYYY-MM-DD')
);


SELECT * FROM leky WHERE popis like '%bolest%';

/*
-- Zadaný email už je v databázi
BEGIN
   vytvor_osobu('920211/1234', 'John', 'Doe', TO_DATE('1990-01-01', 'YYYY-MM-DD'), 'Praha', 'M', 123456789, 'jan.novak@email.com');
END;
/
*/

/*
-- Daný lékař má již v tomto čase vyšetření, bude zachyceno triggerem
INSERT INTO vysetreni (RC_pacient, RC_lekar, datum, popis)
VALUES ('090101/0001', '800101/1234', TO_DATE('2023-03-26 12:00', 'YYYY-MM-DD HH24:MI'), 'Operace srdce.');
*/

-- pouzije proceduru k vyhledani leku obsahujici "bolest" v popisu
BEGIN
   vyhledat_lek('bolest');
END;
/

EXPLAIN PLAN FOR
SELECT jmeno, COUNT(*) 
FROM osoba
NATURAL JOIN pacient
WHERE datum_narozeni BETWEEN TO_DATE('2001-01-01', 'YYYY-MM-DD') AND TO_DATE('2022-12-31', 'YYYY-MM-DD')
GROUP BY jmeno;

SELECT operation, options, partition_start, partition_stop, partition_id
   FROM plan_table;


--index pro optimalizaci vyhledavani dle data narozeni
CREATE INDEX index_osoba ON osoba (datum_narozeni);

EXPLAIN PLAN FOR
SELECT jmeno, COUNT(*) 
FROM osoba
NATURAL JOIN pacient
WHERE datum_narozeni BETWEEN TO_DATE('2001-01-01', 'YYYY-MM-DD') AND TO_DATE('2022-12-31', 'YYYY-MM-DD')
GROUP BY jmeno;

SELECT operation, options, partition_start, partition_stop, partition_id
   FROM plan_table;

DELETE FROM plan_table;
COMMIT;

-- opravneni
GRANT SELECT ON XVOROB02.osoba TO XKANKO01;
GRANT SELECT ON XVOROB02.pacient TO XKANKO01;

DROP MATERIALIZED VIEW XKANKO01_pohled;

CREATE MATERIALIZED VIEW XKANKO01_pohled
AS SELECT o.jmeno, COUNT(*) AS pocet_pacientu
   FROM XVOROB02.osoba o
   NATURAL JOIN XVOROB02.pacient p
   WHERE o.datum_narozeni BETWEEN TO_DATE('2001-01-01', 'YYYY-MM-DD') AND TO_DATE('2022-12-31', 'YYYY-MM-DD')
   GROUP BY o.jmeno;

-- Selcet s WITH a CASE, ziska vhodné oslovení pro osoby
WITH pohlavi_osob AS (
  SELECT jmeno, prijmeni, 
    CASE 
      WHEN pohlavi = 'M' THEN 'Vážený Pan'
      WHEN pohlavi = 'Z' THEN 'Vážená Paní'
      ELSE 'Vážený/á'
    END AS Pozdrav
  FROM osoba
)
SELECT * FROM pohlavi_osob;