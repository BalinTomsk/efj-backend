---------------------------------------------------------------------------------
-- Ontario 2026 zone-wide fishing regulations  (state = 'ON', generated)
-- Source: https://www.ontario.ca/document/ontario-fishing-regulations-summary
-- Zone-wide rules: zone_id = FMZ #, Lake_id = NULL. Named-water EXCEPTIONS not included.
-- Combined species: fish_id = primary, chain = partner. Verbatim rule in regulations_text.
-- regulations_code: 1 = closed all year, 8 = open. reg_year/regulations_part use defaults.
-- Idempotent: each zone first deletes its own ON / zone / 2026 zone-wide rows.
---------------------------------------------------------------------------------
------------------------------ FMZ 1 ------------------------------
DECLARE @z int = 1; DECLARE @link nvarchar(255) = N'https://www.ontario.ca/document/ontario-fishing-regulations-summary/fisheries-management-zone-1';
DELETE FROM dbo.regulations WHERE state='ON' AND zone_id=@z AND Lake_id IS NULL AND reg_year=2026;
INSERT INTO dbo.regulations
    (state, zone_id, Lake_id, fish_id, chain, resident_type, regulations_date_start, regulations_start, regulations_date_end, regulations_end, regulations_sport, regulations_consr, min_length_cm, slot_min_cm, slot_max_cm, slot_over_limit, method_flags, regulations_code, regulations_link, regulations_text)
VALUES
('ON', @z, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, 5, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Aggregate limit for all trout and salmon (including splake): S-5 and C-2 total daily catch and possession for all species combined.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Trout, Brook'), NULL, 0, '2026-01-01', NULL, '2026-09-30', NULL, 5, 2, NULL, NULL, 40, 1, NULL, 8, @link, N'Brook trout. January 1 to September 30. S-5 and C-2; not more than 1 greater than 40 cm.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Sturgeon, Lake'), NULL, 0, NULL, NULL, NULL, NULL, 0, 0, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Lake sturgeon. Season: January 1 to April 30 and July 1 to December 31. S-0 and C-0.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Trout, Lake'), NULL, 0, NULL, NULL, NULL, NULL, 3, 1, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Lake trout. Open all year. S-3 and C-1.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Whitefish, Lake'), NULL, 0, NULL, NULL, NULL, NULL, 12, 6, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Lake whitefish. Open all year. S-12 and C-6.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Pike, Northern'), NULL, 0, NULL, NULL, NULL, NULL, 6, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Northern pike. Open all year. S-6; not more than 2 greater than 61 cm, of which not more than 1 greater than 86 cm, and C-2.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Walleye'), (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Sauger'), 0, NULL, NULL, NULL, NULL, 4, 2, NULL, NULL, 46, 1, NULL, 8, @link, N'Walleye and sauger combined. Open all year. S-4 and C-2; not more than 1 greater than 46 cm.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Perch, Yellow'), NULL, 0, NULL, NULL, NULL, NULL, 50, 25, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Yellow perch. Open all year. S-50 and C-25.')
;
GO

------------------------------ FMZ 2 ------------------------------
DECLARE @z int = 2; DECLARE @link nvarchar(255) = N'https://www.ontario.ca/document/ontario-fishing-regulations-summary/fisheries-management-zone-2';
DELETE FROM dbo.regulations WHERE state='ON' AND zone_id=@z AND Lake_id IS NULL AND reg_year=2026;
INSERT INTO dbo.regulations
    (state, zone_id, Lake_id, fish_id, chain, resident_type, regulations_date_start, regulations_start, regulations_date_end, regulations_end, regulations_sport, regulations_consr, min_length_cm, slot_min_cm, slot_max_cm, slot_over_limit, method_flags, regulations_code, regulations_link, regulations_text)
VALUES
('ON', @z, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, 5, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Aggregate limit for all trout and salmon (including splake): S-5 and C-2 total daily catch and possession for all species combined.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Trout, Brook'), NULL, 0, '2026-01-01', NULL, NULL, N'Labour Day', 5, 2, NULL, NULL, 30, 1, NULL, 8, @link, N'Brook trout. January 1 to Labour Day. S-5 and C-2; not more than 1 greater than 30 cm.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Trout, Brown'), NULL, 0, NULL, NULL, NULL, NULL, 5, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Brown trout. Open all year. S-5 and C-2.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Sturgeon, Lake'), NULL, 0, NULL, NULL, NULL, NULL, 0, 0, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Lake sturgeon. Season: January 1 to April 30 and July 1 to December 31. S-0 and C-0.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Trout, Lake'), NULL, 0, '2026-01-01', NULL, '2026-09-30', NULL, 2, 1, NULL, NULL, 56, 1, NULL, 8, @link, N'Lake trout. January 1 to September 30. S-2; not more than 1 greater than 56 cm from September 1 to September 30. C-1; any size.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Whitefish, Lake'), NULL, 0, NULL, NULL, NULL, NULL, 12, 6, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Lake whitefish. Open all year. S-12 and C-6.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Bass, Smallmouth'), (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Bass, Largemouth'), 0, NULL, NULL, NULL, NULL, 4, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Largemouth and smallmouth bass combined. Open all year. S-4 and C-2; must be less than 35 cm from January 1 to June 30 and December 1 to December 31; no size limit July 1 to November 30.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Muskellunge'), NULL, 0, NULL, N'third Saturday in June', '2026-12-15', NULL, 1, 0, 91, NULL, NULL, NULL, NULL, 8, @link, N'Muskellunge. Third Saturday in June to December 15. S-1; must be greater than 91 cm, and C-0.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Pike, Northern'), NULL, 0, NULL, NULL, NULL, NULL, 4, 2, NULL, 70, 90, 1, NULL, 8, @link, N'Northern pike. Open all year. S-4 and C-2; none between 70-90 cm, not more than 1 greater than 90 cm.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Trout, Rainbow'), NULL, 0, NULL, NULL, NULL, NULL, 5, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Rainbow trout. Open all year. S-5 and C-2.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Splake'), NULL, 0, NULL, NULL, NULL, NULL, 5, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Splake. Open all year. S-5 and C-2.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Sunfish, Bluegill'), NULL, 0, NULL, NULL, NULL, NULL, 50, 25, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Sunfish (bluegill, pumpkinseed and other sunfish). Open all year. S-50 and C-25.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Walleye'), (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Sauger'), 0, NULL, NULL, NULL, NULL, 4, 2, NULL, NULL, 46, 1, NULL, 8, @link, N'Walleye and sauger combined. January 1 to April 14 and third Saturday in May to December 31. S-4 and C-2; not more than 1 greater than 46 cm.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Perch, Yellow'), NULL, 0, NULL, NULL, NULL, NULL, 50, 25, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Yellow perch. Open all year. S-50 and C-25.')
;
GO

------------------------------ FMZ 3 ------------------------------
DECLARE @z int = 3; DECLARE @link nvarchar(255) = N'https://www.ontario.ca/document/ontario-fishing-regulations-summary/fisheries-management-zone-3';
DELETE FROM dbo.regulations WHERE state='ON' AND zone_id=@z AND Lake_id IS NULL AND reg_year=2026;
INSERT INTO dbo.regulations
    (state, zone_id, Lake_id, fish_id, chain, resident_type, regulations_date_start, regulations_start, regulations_date_end, regulations_end, regulations_sport, regulations_consr, min_length_cm, slot_min_cm, slot_max_cm, slot_over_limit, method_flags, regulations_code, regulations_link, regulations_text)
VALUES
('ON', @z, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, 5, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Aggregate limit for all trout and salmon (including splake): S-5 and C-2 total daily catch and possession for all species combined.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Trout, Brook'), NULL, 0, '2026-01-01', NULL, '2026-09-15', NULL, 5, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Brook trout. January 1 to September 15. S-5 and C-2.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Sturgeon, Lake'), NULL, 0, NULL, NULL, NULL, NULL, 0, 0, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Lake sturgeon. Season: January 1 to April 15 and July 1 to December 31. S-0 and C-0.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Trout, Lake'), NULL, 0, '2026-01-01', NULL, '2026-09-30', NULL, 3, 1, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Lake trout. January 1 to September 30. S-3 and C-1.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Whitefish, Lake'), NULL, 0, NULL, NULL, NULL, NULL, 12, 6, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Lake whitefish. Open all year. S-12 and C-6.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Bass, Smallmouth'), (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Bass, Largemouth'), 0, NULL, NULL, NULL, NULL, 6, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Largemouth and smallmouth bass combined. Open all year. S-6 and C-2.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Pike, Northern'), NULL, 0, NULL, NULL, NULL, NULL, 6, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Northern pike. Open all year. S-6; not more than 2 greater than 61 cm, of which not more than 1 greater than 86 cm, and C-2; not more than 1 greater than 61 cm.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Splake'), NULL, 0, NULL, NULL, NULL, NULL, 5, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Splake. Open all year. S-5 and C-2.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Sunfish, Bluegill'), NULL, 0, NULL, NULL, NULL, NULL, 50, 25, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Sunfish (bluegill, pumpkinseed and other sunfish). Open all year. S-50 and C-25.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Walleye'), (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Sauger'), 0, NULL, NULL, NULL, NULL, 4, 2, NULL, NULL, 46, 1, NULL, 8, @link, N'Walleye and sauger combined. January 1 to April 14 and third Saturday in May to December 31. S-4 and C-2; not more than 1 greater than 46 cm.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Perch, Yellow'), NULL, 0, NULL, NULL, NULL, NULL, 50, 25, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Yellow perch. Open all year. S-50 and C-25.')
;
GO

------------------------------ FMZ 4 ------------------------------
DECLARE @z int = 4; DECLARE @link nvarchar(255) = N'https://www.ontario.ca/document/ontario-fishing-regulations-summary/fisheries-management-zone-4';
DELETE FROM dbo.regulations WHERE state='ON' AND zone_id=@z AND Lake_id IS NULL AND reg_year=2026;
INSERT INTO dbo.regulations
    (state, zone_id, Lake_id, fish_id, chain, resident_type, regulations_date_start, regulations_start, regulations_date_end, regulations_end, regulations_sport, regulations_consr, min_length_cm, slot_min_cm, slot_max_cm, slot_over_limit, method_flags, regulations_code, regulations_link, regulations_text)
VALUES
('ON', @z, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, 5, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Aggregate limit for all trout and salmon (including splake): S-5 and C-2 total daily catch and possession for all species combined.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Trout, Brook'), NULL, 0, '2026-01-01', NULL, NULL, N'Labour Day', 5, 2, NULL, NULL, 30, 1, NULL, 8, @link, N'Brook trout. January 1 to Labour Day. S-5 and C-2; not more than 1 greater than 30 cm.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Crappie, Black'), NULL, 0, NULL, NULL, NULL, NULL, 15, 10, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Crappie. Open all year. S-15 and C-10.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Sturgeon, Lake'), NULL, 0, NULL, NULL, NULL, NULL, 0, 0, NULL, NULL, NULL, NULL, NULL, 1, @link, N'Lake sturgeon. Closed all year.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Trout, Lake'), NULL, 0, '2026-01-01', NULL, '2026-09-30', NULL, 2, 1, NULL, NULL, 56, 1, NULL, 8, @link, N'Lake trout. January 1 to September 30. S-2; not more than 1 greater than 56 cm. C-1; no size limit.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Whitefish, Lake'), NULL, 0, NULL, NULL, NULL, NULL, 12, 6, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Lake whitefish. Open all year. S-12 and C-6.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Bass, Smallmouth'), (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Bass, Largemouth'), 0, NULL, NULL, NULL, NULL, 4, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Largemouth and smallmouth bass combined. Open all year. Must be less than 35 cm Jan 1-Jun 30 and Dec 1-Dec 31, S-2 and C-1; no size limit Jul 1-Nov 30, S-4 and C-2.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Muskellunge'), NULL, 0, NULL, N'third Saturday in June', '2026-12-15', NULL, 1, 0, 102, NULL, NULL, NULL, NULL, 8, @link, N'Muskellunge. Third Saturday in June to December 15. S-1; must be greater than 102 cm, and C-0.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Pike, Northern'), NULL, 0, NULL, NULL, NULL, NULL, 4, 2, NULL, 70, 90, 1, NULL, 8, @link, N'Northern pike. Open all year. S-4 and C-2; none between 70-90 cm, not more than 1 greater than 90 cm.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Trout, Rainbow'), NULL, 0, NULL, NULL, NULL, NULL, 5, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Rainbow trout. Open all year. S-5 and C-2.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Splake'), NULL, 0, NULL, NULL, NULL, NULL, 5, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Splake. Open all year. S-5 and C-2.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Sunfish, Bluegill'), NULL, 0, NULL, NULL, NULL, NULL, 50, 25, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Sunfish (bluegill, pumpkinseed and other sunfish). Open all year. S-50 and C-25.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Perch, Yellow'), NULL, 0, NULL, NULL, NULL, NULL, 50, 25, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Yellow perch. Open all year. S-50 and C-25.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Walleye'), (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Sauger'), 0, NULL, NULL, NULL, NULL, 4, 2, NULL, NULL, 46, 1, NULL, 8, @link, N'Walleye and sauger combined. January 1 to April 14 and third Saturday in May to December 31. S-4 and C-2; not more than 1 greater than 46 cm.')
;
GO

------------------------------ FMZ 5 ------------------------------
DECLARE @z int = 5; DECLARE @link nvarchar(255) = N'https://www.ontario.ca/document/ontario-fishing-regulations-summary/fisheries-management-zone-5';
DELETE FROM dbo.regulations WHERE state='ON' AND zone_id=@z AND Lake_id IS NULL AND reg_year=2026;
INSERT INTO dbo.regulations
    (state, zone_id, Lake_id, fish_id, chain, resident_type, regulations_date_start, regulations_start, regulations_date_end, regulations_end, regulations_sport, regulations_consr, min_length_cm, slot_min_cm, slot_max_cm, slot_over_limit, method_flags, regulations_code, regulations_link, regulations_text)
VALUES
('ON', @z, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, 5, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Aggregate limit for all trout and salmon (including splake): S-5 and C-2 total daily catch and possession for all species combined.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Trout, Brook'), NULL, 0, NULL, NULL, NULL, NULL, 5, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Brook trout. Open all year. S-5 and C-2.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Trout, Brown'), NULL, 0, NULL, NULL, NULL, NULL, 5, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Brown trout. Open all year. S-5 and C-2.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Crappie, Black'), NULL, 0, NULL, NULL, NULL, NULL, 10, 5, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Crappie. Open all year. S-10 and C-5.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Sturgeon, Lake'), NULL, 0, NULL, NULL, NULL, NULL, 0, 0, NULL, NULL, NULL, NULL, NULL, 1, @link, N'Lake sturgeon. Closed all year.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Trout, Lake'), NULL, 1, '2026-01-01', NULL, '2026-09-30', NULL, 2, 1, NULL, NULL, 56, 1, NULL, 8, @link, N'Lake trout (Ontario/Canadian residents). January 1 to September 30. S-2; not more than 1 greater than 56 cm from September 1 to September 30, and C-1; no size limit.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Trout, Lake'), NULL, 2, '2026-01-01', NULL, '2026-09-30', NULL, 1, 1, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Lake trout (non-Canadian residents). January 1 to September 30. Daily catch and retain: S-1 and C-1, no size limit. Possession: S-2, not more than 1 greater than 56 cm from September 1 to September 30, and C-1.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Whitefish, Lake'), NULL, 0, NULL, NULL, NULL, NULL, 12, 6, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Lake whitefish. Open all year. S-12 and C-6.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Bass, Smallmouth'), (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Bass, Largemouth'), 0, NULL, NULL, NULL, NULL, 4, 2, NULL, 35, NULL, NULL, NULL, 8, @link, N'Largemouth and smallmouth bass combined. Open all year. S-4 and C-2; must be less than 35 cm from January 1 to June 30.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Muskellunge'), NULL, 0, NULL, N'third Saturday in June', '2026-12-15', NULL, 1, 0, 102, NULL, NULL, NULL, NULL, 8, @link, N'Muskellunge. Third Saturday in June to December 15. S-1; must be greater than 102 cm, and C-0.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Pike, Northern'), NULL, 0, NULL, NULL, NULL, NULL, 4, 2, NULL, NULL, 75, 0, NULL, 8, @link, N'Northern pike. Open all year. S-4 and C-2; none greater than 75 cm.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Trout, Rainbow'), NULL, 0, NULL, NULL, NULL, NULL, 5, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Rainbow trout. Open all year. S-5 and C-2.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Splake'), NULL, 0, NULL, NULL, NULL, NULL, 5, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Splake. Open all year. S-5 and C-2.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Sunfish, Bluegill'), NULL, 0, NULL, NULL, NULL, NULL, 50, 25, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Sunfish (bluegill, pumpkinseed and other sunfish). Open all year. S-50 and C-25.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Walleye'), (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Sauger'), 1, NULL, NULL, NULL, NULL, 4, 2, NULL, NULL, 46, 1, NULL, 8, @link, N'Walleye and sauger combined (Ontario/Canadian residents). January 1 to April 14 and third Saturday in May to December 31. S-4 and C-2; not more than 1 greater than 46 cm.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Walleye'), (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Sauger'), 2, NULL, NULL, NULL, NULL, 2, 2, NULL, NULL, 46, 1, NULL, 8, @link, N'Walleye and sauger combined (non-Canadian residents). Daily catch and retain: S-2 and C-2; not more than 1 greater than 46 cm. Possession: S-4 and C-2; not more than 1 greater than 46 cm.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Perch, Yellow'), NULL, 0, NULL, NULL, NULL, NULL, 50, 25, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Yellow perch. Open all year. S-50 and C-25.')
;
GO

------------------------------ FMZ 6 ------------------------------
DECLARE @z int = 6; DECLARE @link nvarchar(255) = N'https://www.ontario.ca/document/ontario-fishing-regulations-summary/fisheries-management-zone-6';
DELETE FROM dbo.regulations WHERE state='ON' AND zone_id=@z AND Lake_id IS NULL AND reg_year=2026;
INSERT INTO dbo.regulations
    (state, zone_id, Lake_id, fish_id, chain, resident_type, regulations_date_start, regulations_start, regulations_date_end, regulations_end, regulations_sport, regulations_consr, min_length_cm, slot_min_cm, slot_max_cm, slot_over_limit, method_flags, regulations_code, regulations_link, regulations_text)
VALUES
('ON', @z, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, 5, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Aggregate limit for all trout and salmon (including splake): S-5 and C-2 total daily catch and possession for all species combined.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Salmon, Atlantic'), NULL, 0, NULL, NULL, NULL, NULL, 1, 0, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Atlantic salmon. Open all year. S-1 and C-0.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Trout, Brook'), NULL, 0, NULL, N'fourth Saturday in April', NULL, N'Labour Day', 5, 2, NULL, NULL, 30, 1, NULL, 8, @link, N'Brook trout. Fourth Saturday in April to Labour Day. S-5 and C-2; not more than 1 greater than 30 cm.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Trout, Brown'), NULL, 0, NULL, NULL, NULL, NULL, 5, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Brown trout. Open all year. S-5 and C-2.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Catfish, Channel'), NULL, 0, NULL, NULL, NULL, NULL, 12, 6, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Channel catfish. Open all year. S-12 and C-6.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Crappie, Black'), NULL, 0, NULL, NULL, NULL, NULL, 15, 10, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Crappie. Open all year. S-15 and C-10.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Sturgeon, Lake'), NULL, 0, NULL, NULL, NULL, NULL, 0, 0, NULL, NULL, NULL, NULL, NULL, 1, @link, N'Lake sturgeon. Closed all year.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Trout, Lake'), NULL, 0, '2026-01-01', NULL, '2026-09-30', NULL, 2, 1, NULL, NULL, 56, 1, NULL, 8, @link, N'Lake trout. January 1 to September 30. S-2; not more than 1 greater than 56 cm from September 1 to September 30, no size limit the rest of the season, and C-1; no size limit.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Whitefish, Lake'), NULL, 0, NULL, NULL, NULL, NULL, 12, 6, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Lake whitefish. Open all year. S-12 and C-6.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Bass, Smallmouth'), (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Bass, Largemouth'), 0, NULL, NULL, NULL, NULL, 4, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Largemouth and smallmouth bass combined. Open all year. S-4 and C-2.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Muskellunge'), NULL, 0, NULL, N'third Saturday in June', '2026-12-15', NULL, 1, 0, 91, NULL, NULL, NULL, NULL, 8, @link, N'Muskellunge. Third Saturday in June to December 15. S-1; must be greater than 91 cm, and C-0.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Pike, Northern'), NULL, 0, NULL, NULL, NULL, NULL, 4, 2, NULL, NULL, 70, 1, NULL, 8, @link, N'Northern pike. Open all year. S-4 and C-2; not more than 1 greater than or equal to 70 cm.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Salmon, Chinook'), NULL, 0, NULL, NULL, NULL, NULL, 5, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Pacific salmon (Chinook, Coho and other Pacific salmon). Open all year. S-5 and C-2.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Trout, Rainbow'), NULL, 0, NULL, NULL, NULL, NULL, 1, 0, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Rainbow trout. Open all year. S-1 and C-0.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Splake'), NULL, 0, NULL, NULL, NULL, NULL, 5, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Splake. Open all year. S-5 and C-2.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Sunfish, Bluegill'), NULL, 0, NULL, NULL, NULL, NULL, 50, 25, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Sunfish (bluegill, pumpkinseed and other sunfish). Open all year. S-50 and C-25.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Walleye'), (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Sauger'), 0, NULL, NULL, NULL, NULL, 4, 2, NULL, NULL, 46, 1, NULL, 8, @link, N'Walleye and sauger combined. January 1 to April 14 and third Saturday in May to December 31. S-4 and C-2; not more than 1 greater than 46 cm.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Perch, Yellow'), NULL, 0, NULL, NULL, NULL, NULL, 50, 25, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Yellow perch. Open all year. S-50 and C-25.')
;
GO

------------------------------ FMZ 7 ------------------------------
DECLARE @z int = 7; DECLARE @link nvarchar(255) = N'https://www.ontario.ca/document/ontario-fishing-regulations-summary/fisheries-management-zone-7';
DELETE FROM dbo.regulations WHERE state='ON' AND zone_id=@z AND Lake_id IS NULL AND reg_year=2026;
INSERT INTO dbo.regulations
    (state, zone_id, Lake_id, fish_id, chain, resident_type, regulations_date_start, regulations_start, regulations_date_end, regulations_end, regulations_sport, regulations_consr, min_length_cm, slot_min_cm, slot_max_cm, slot_over_limit, method_flags, regulations_code, regulations_link, regulations_text)
VALUES
('ON', @z, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, 5, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Aggregate limit for all trout and salmon (including splake): S-5 and C-2 total daily catch and possession for all species combined.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Salmon, Atlantic'), NULL, 0, NULL, NULL, NULL, NULL, 1, 0, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Atlantic salmon. Open all year. S-1 and C-0.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Trout, Brook'), NULL, 0, '2026-01-01', NULL, NULL, N'Labour Day', 5, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Brook trout. January 1 to Labour Day. S-5; not more than 2 greater than 30 cm, of which not more than 1 greater than 40 cm, and C-2; not more than 1 greater than 30 cm, none greater than 40 cm.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Trout, Brown'), NULL, 0, NULL, NULL, NULL, NULL, 5, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Brown trout. Open all year. S-5 and C-2.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Sturgeon, Lake'), NULL, 0, NULL, NULL, NULL, NULL, 0, 0, NULL, NULL, NULL, NULL, NULL, 1, @link, N'Lake sturgeon. Closed all year.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Trout, Lake'), NULL, 0, '2026-01-01', NULL, '2026-09-30', NULL, 2, 1, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Lake trout. January 1 to September 30. S-2 and C-1.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Whitefish, Lake'), NULL, 0, NULL, NULL, NULL, NULL, 25, 12, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Lake whitefish. Open all year. S-25 and C-12.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Bass, Smallmouth'), (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Bass, Largemouth'), 0, NULL, NULL, NULL, NULL, 6, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Largemouth and smallmouth bass combined. Open all year. S-6 and C-2.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Muskellunge'), NULL, 0, NULL, NULL, NULL, NULL, 0, 0, NULL, NULL, NULL, NULL, NULL, 1, @link, N'Muskellunge. Closed all year.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Pike, Northern'), NULL, 0, NULL, NULL, NULL, NULL, 6, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Northern pike. Open all year. S-6; not more than 2 greater than 61 cm, of which not more than 1 greater than 86 cm, and C-2; not more than 1 greater than 61 cm, none greater than 86 cm.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Salmon, Chinook'), NULL, 0, NULL, NULL, NULL, NULL, 5, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Pacific salmon (Chinook, Coho and other Pacific salmon). Open all year. S-5 and C-2.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Trout, Rainbow'), NULL, 0, NULL, NULL, NULL, NULL, 1, 0, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Rainbow trout. Open all year. S-1 and C-0.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Splake'), NULL, 0, NULL, NULL, NULL, NULL, 5, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Splake. Open all year. S-5 and C-2.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Sunfish, Bluegill'), NULL, 0, NULL, NULL, NULL, NULL, 50, 25, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Sunfish (bluegill, pumpkinseed and other sunfish). Open all year. S-50 and C-25.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Walleye'), (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Sauger'), 0, NULL, NULL, NULL, NULL, 4, 2, NULL, NULL, 46, 1, NULL, 8, @link, N'Walleye and sauger combined. January 1 to April 14 and third Saturday in May to December 31. S-4 and C-2; not more than 1 greater than 46 cm.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Perch, Yellow'), NULL, 0, NULL, NULL, NULL, NULL, 50, 25, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Yellow perch. Open all year. S-50 and C-25.')
;
GO

------------------------------ FMZ 8 ------------------------------
DECLARE @z int = 8; DECLARE @link nvarchar(255) = N'https://www.ontario.ca/document/ontario-fishing-regulations-summary/fisheries-management-zone-8';
DELETE FROM dbo.regulations WHERE state='ON' AND zone_id=@z AND Lake_id IS NULL AND reg_year=2026;
INSERT INTO dbo.regulations
    (state, zone_id, Lake_id, fish_id, chain, resident_type, regulations_date_start, regulations_start, regulations_date_end, regulations_end, regulations_sport, regulations_consr, min_length_cm, slot_min_cm, slot_max_cm, slot_over_limit, method_flags, regulations_code, regulations_link, regulations_text)
VALUES
('ON', @z, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, 5, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Aggregate limit for all trout and salmon (including splake): S-5 and C-2 total daily catch and possession for all species combined.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Trout, Brook'), NULL, 0, '2026-01-01', NULL, '2026-09-15', NULL, 5, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Brook trout. January 1 to September 15. S-5 and C-2.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Sturgeon, Lake'), NULL, 0, NULL, NULL, NULL, NULL, 0, 0, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Lake sturgeon. Season: January 1 to April 30 and July 1 to December 31. S-0 and C-0.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Trout, Lake'), NULL, 0, '2026-02-15', NULL, '2026-09-30', NULL, 3, 1, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Lake trout. February 15 to March 15 and third Saturday in May to September 30. S-3 and C-1.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Whitefish, Lake'), NULL, 0, NULL, NULL, NULL, NULL, 25, 12, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Lake whitefish. Open all year. S-25 and C-12.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Bass, Smallmouth'), (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Bass, Largemouth'), 0, NULL, NULL, NULL, NULL, 6, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Largemouth and smallmouth bass combined. Open all year. S-6 and C-2.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Pike, Northern'), NULL, 0, NULL, NULL, NULL, NULL, 6, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Northern pike. Open all year. S-6; not more than 2 greater than 61 cm, of which not more than 1 greater than 86 cm, and C-2; not more than 1 greater than 61 cm, none greater than 86 cm.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Trout, Rainbow'), NULL, 0, NULL, NULL, NULL, NULL, 5, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Rainbow trout. Open all year. S-5 and C-2.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Splake'), NULL, 0, NULL, NULL, NULL, NULL, 5, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Splake. Open all year. S-5 and C-2.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Sunfish, Bluegill'), NULL, 0, NULL, NULL, NULL, NULL, 50, 25, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Sunfish (bluegill, pumpkinseed and other sunfish). Open all year. S-50 and C-25.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Walleye'), (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Sauger'), 0, NULL, NULL, NULL, NULL, 4, 2, NULL, NULL, 46, 1, NULL, 8, @link, N'Walleye and sauger combined. January 1 to April 14 and third Saturday in May to December 31. S-4 and C-2; not more than 1 greater than 46 cm.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Perch, Yellow'), NULL, 0, NULL, NULL, NULL, NULL, 50, 25, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Yellow perch. Open all year. S-50 and C-25.')
;
GO

------------------------------ FMZ 9 ------------------------------
DECLARE @z int = 9; DECLARE @link nvarchar(255) = N'https://www.ontario.ca/document/ontario-fishing-regulations-summary/fisheries-management-zone-9';
DELETE FROM dbo.regulations WHERE state='ON' AND zone_id=@z AND Lake_id IS NULL AND reg_year=2026;
INSERT INTO dbo.regulations
    (state, zone_id, Lake_id, fish_id, chain, resident_type, regulations_date_start, regulations_start, regulations_date_end, regulations_end, regulations_sport, regulations_consr, min_length_cm, slot_min_cm, slot_max_cm, slot_over_limit, method_flags, regulations_code, regulations_link, regulations_text)
VALUES
('ON', @z, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, 5, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Aggregate limit for all trout and salmon (including splake): S-5 and C-2 total daily catch and possession for all species combined.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Salmon, Atlantic'), NULL, 0, NULL, NULL, NULL, NULL, 1, 0, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Atlantic salmon. Open all year. S-1 and C-0.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Trout, Brook'), NULL, 0, NULL, N'fourth Saturday in April', NULL, N'Labour Day', 1, 0, 56, NULL, NULL, NULL, NULL, 8, @link, N'Brook trout. Fourth Saturday in April to Labour Day. S-1; must be greater than 56 cm, and C-0.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Trout, Brown'), NULL, 0, NULL, NULL, NULL, NULL, 5, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Brown trout. Open all year. S-5 and C-2.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Catfish, Channel'), NULL, 0, NULL, NULL, NULL, NULL, 12, 6, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Channel catfish. Open all year. S-12 and C-6.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Crappie, Black'), NULL, 0, NULL, NULL, NULL, NULL, 30, 10, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Crappie. Open all year. S-30 and C-10.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Sturgeon, Lake'), NULL, 0, NULL, NULL, NULL, NULL, 0, 0, NULL, NULL, NULL, NULL, NULL, 1, @link, N'Lake sturgeon. Closed all year.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Trout, Lake'), NULL, 0, '2026-01-01', NULL, '2026-09-30', NULL, 3, 1, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Lake trout. January 1 to September 30. S-3 and C-1.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Whitefish, Lake'), NULL, 0, NULL, NULL, NULL, NULL, 12, 6, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Lake whitefish. Open all year. S-12 and C-6.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Bass, Smallmouth'), (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Bass, Largemouth'), 0, NULL, NULL, NULL, NULL, 6, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Largemouth and smallmouth bass combined. Open all year. S-6 and C-2.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Muskellunge'), NULL, 0, NULL, N'third Saturday in June', '2026-12-15', NULL, 1, 0, 137, NULL, NULL, NULL, NULL, 8, @link, N'Muskellunge. Third Saturday in June to December 15. S-1; must be greater than 137 cm, and C-0.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Pike, Northern'), NULL, 0, NULL, NULL, NULL, NULL, 4, 2, NULL, 70, 90, 1, NULL, 8, @link, N'Northern pike. Open all year. S-4 and C-2; none between 70-90 cm, not more than 1 greater than 90 cm.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Salmon, Chinook'), NULL, 0, NULL, NULL, NULL, NULL, 5, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Pacific salmon (Chinook, Coho and other Pacific salmon). Open all year. S-5 and C-2.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Trout, Rainbow'), NULL, 0, NULL, NULL, NULL, NULL, 1, 0, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Rainbow trout. Open all year. S-1 and C-0.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Splake'), NULL, 0, '2026-01-01', NULL, '2026-09-30', NULL, 3, 1, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Splake. January 1 to September 30. S-3 and C-1.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Sunfish, Bluegill'), NULL, 0, NULL, NULL, NULL, NULL, 50, 25, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Sunfish (bluegill, pumpkinseed and other sunfish). Open all year. S-50 and C-25.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Walleye'), (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Sauger'), 0, NULL, NULL, NULL, NULL, 2, 1, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Walleye and sauger combined. January 1 to April 14 and third Saturday in May to December 31. S-2 and C-1.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Perch, Yellow'), NULL, 0, NULL, NULL, NULL, NULL, 25, 12, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Yellow perch. Open all year. S-25 and C-12.')
;
GO

------------------------------ FMZ 10 ------------------------------
DECLARE @z int = 10; DECLARE @link nvarchar(255) = N'https://www.ontario.ca/document/ontario-fishing-regulations-summary/fisheries-management-zone-10';
DELETE FROM dbo.regulations WHERE state='ON' AND zone_id=@z AND Lake_id IS NULL AND reg_year=2026;
INSERT INTO dbo.regulations
    (state, zone_id, Lake_id, fish_id, chain, resident_type, regulations_date_start, regulations_start, regulations_date_end, regulations_end, regulations_sport, regulations_consr, min_length_cm, slot_min_cm, slot_max_cm, slot_over_limit, method_flags, regulations_code, regulations_link, regulations_text)
VALUES
('ON', @z, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, 5, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Aggregate limit for all trout and salmon (including splake): S-5 and C-2 total daily catch and possession for all species combined.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Salmon, Atlantic'), NULL, 0, '2026-01-01', NULL, '2026-09-30', NULL, 1, 0, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Atlantic salmon. January 1 to September 30. S-1 and C-0.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Trout, Brook'), NULL, 0, '2026-01-01', NULL, '2026-09-30', NULL, 5, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Brook trout. January 1 to September 30. S-5 and C-2.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Trout, Brown'), NULL, 0, NULL, NULL, NULL, NULL, 5, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Brown trout. Open all year. S-5 and C-2.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Catfish, Channel'), NULL, 0, NULL, NULL, NULL, NULL, 12, 6, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Channel catfish. Open all year. S-12 and C-6.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Crappie, Black'), NULL, 0, NULL, NULL, NULL, NULL, 30, 10, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Crappie. Open all year. S-30 and C-10.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Sturgeon, Lake'), NULL, 0, NULL, NULL, NULL, NULL, 0, 0, NULL, NULL, NULL, NULL, NULL, 1, @link, N'Lake sturgeon. Closed all year.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Trout, Lake'), NULL, 0, '2026-01-01', NULL, NULL, N'Labour Day', 2, 1, NULL, NULL, 40, 1, NULL, 8, @link, N'Lake trout. January 1 to Labour Day. S-2; not more than 1 greater than 40 cm, and C-1.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Whitefish, Lake'), NULL, 0, NULL, NULL, NULL, NULL, 12, 6, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Lake whitefish. Open all year. S-12 and C-6.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Bass, Smallmouth'), (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Bass, Largemouth'), 0, NULL, N'third Saturday in June', '2026-11-30', NULL, 6, 3, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Largemouth and smallmouth bass combined. Third Saturday in June to November 30. S-6 and C-3.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Muskellunge'), NULL, 0, NULL, N'third Saturday in June', '2026-12-15', NULL, 1, 0, 122, NULL, NULL, NULL, NULL, 8, @link, N'Muskellunge. Third Saturday in June to December 15. S-1; must be greater than 122 cm, and C-0.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Pike, Northern'), NULL, 0, NULL, NULL, NULL, NULL, 6, 2, NULL, NULL, 86, 1, NULL, 8, @link, N'Northern pike. Open all year. S-6; not more than 1 greater than 61 cm, none greater than 86 cm, and C-2; none greater than 61 cm.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Salmon, Chinook'), NULL, 0, NULL, NULL, NULL, NULL, 5, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Pacific salmon (Chinook, Coho and other Pacific salmon). Open all year. S-5 and C-2.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Trout, Rainbow'), NULL, 0, NULL, NULL, NULL, NULL, 2, 1, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Rainbow trout. Open all year. S-2 and C-1.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Splake'), NULL, 0, NULL, NULL, NULL, NULL, 5, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Splake. Open all year. S-5 and C-2.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Sunfish, Bluegill'), NULL, 0, NULL, NULL, NULL, NULL, 50, 25, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Sunfish (bluegill, pumpkinseed and other sunfish). Open all year. S-50 and C-25.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Walleye'), (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Sauger'), 0, NULL, NULL, NULL, NULL, 4, 2, NULL, NULL, 46, 1, NULL, 8, @link, N'Walleye and sauger combined. January 1 to third Sunday in March and third Saturday in May to December 31. S-4 and C-2; none greater than 46 cm.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Perch, Yellow'), NULL, 0, NULL, NULL, NULL, NULL, 50, 25, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Yellow perch. Open all year. S-50 and C-25.')
;
GO

------------------------------ FMZ 11 ------------------------------
DECLARE @z int = 11; DECLARE @link nvarchar(255) = N'https://www.ontario.ca/document/ontario-fishing-regulations-summary/fisheries-management-zone-11';
DELETE FROM dbo.regulations WHERE state='ON' AND zone_id=@z AND Lake_id IS NULL AND reg_year=2026;
INSERT INTO dbo.regulations
    (state, zone_id, Lake_id, fish_id, chain, resident_type, regulations_date_start, regulations_start, regulations_date_end, regulations_end, regulations_sport, regulations_consr, min_length_cm, slot_min_cm, slot_max_cm, slot_over_limit, method_flags, regulations_code, regulations_link, regulations_text)
VALUES
('ON', @z, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, 5, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Aggregate limit for all trout and salmon (including splake): S-5 and C-2 total daily catch and possession for all species combined.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Salmon, Atlantic'), NULL, 0, NULL, NULL, NULL, NULL, 0, 0, NULL, NULL, NULL, NULL, NULL, 1, @link, N'Atlantic salmon. Closed all year.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Trout, Brook'), NULL, 0, '2026-02-15', NULL, '2026-09-30', NULL, 5, 2, NULL, NULL, 31, 1, NULL, 8, @link, N'Brook trout. February 15 to September 30. S-5; not more than 1 greater than 31 cm, and C-2; none greater than 31 cm.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Trout, Brown'), NULL, 0, NULL, N'fourth Saturday in April', '2026-09-30', NULL, 5, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Brown trout. Fourth Saturday in April to September 30. S-5 and C-2.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Catfish, Channel'), NULL, 0, NULL, NULL, NULL, NULL, 12, 6, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Channel catfish. Open all year. S-12 and C-6.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Crappie, Black'), NULL, 0, NULL, NULL, NULL, NULL, 30, 10, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Crappie. Open all year. S-30 and C-10.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Sturgeon, Lake'), NULL, 0, NULL, NULL, NULL, NULL, 0, 0, NULL, NULL, NULL, NULL, NULL, 1, @link, N'Lake sturgeon. Closed all year.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Trout, Lake'), NULL, 0, '2026-02-15', NULL, NULL, N'Labour Day', 2, 1, NULL, NULL, 40, 1, NULL, 8, @link, N'Lake trout. February 15 to third Sunday in March and third Saturday in May to Labour Day. S-2; not more than 1 greater than 40 cm, and C-1.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Whitefish, Lake'), NULL, 0, NULL, NULL, NULL, NULL, 12, 6, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Lake whitefish. Open all year. S-12 and C-6.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Bass, Smallmouth'), (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Bass, Largemouth'), 0, NULL, NULL, NULL, NULL, 6, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Largemouth and smallmouth bass combined. January 1 to third Sunday in March and third Saturday in May to December 31. S-6 and C-2.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Muskellunge'), NULL, 0, NULL, N'third Saturday in June', '2026-12-15', NULL, 1, 0, 122, NULL, NULL, NULL, NULL, 8, @link, N'Muskellunge. Third Saturday in June to December 15. S-1; must be greater than 122 cm, and C-0.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Pike, Northern'), NULL, 0, NULL, NULL, NULL, NULL, 6, 2, NULL, NULL, 86, 1, NULL, 8, @link, N'Northern pike. January 1 to third Sunday in March and third Saturday in May to December 31. S-6; not more than 2 greater than 61 cm, of which not more than 1 greater than 86 cm, and C-2; not more than 1 greater than 61 cm, none greater than 86 cm.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Trout, Rainbow'), NULL, 0, NULL, NULL, NULL, NULL, 5, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Rainbow trout. Open all year. S-5 and C-2.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Splake'), NULL, 0, NULL, NULL, NULL, NULL, 5, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Splake. Open all year. S-5 and C-2.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Sunfish, Bluegill'), NULL, 0, NULL, NULL, NULL, NULL, 50, 25, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Sunfish (bluegill, pumpkinseed and other sunfish). Open all year. S-50 and C-25.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Walleye'), (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Sauger'), 0, NULL, NULL, NULL, NULL, 4, 2, NULL, 43, 60, 1, NULL, 8, @link, N'Walleye and sauger combined. January 1 to third Sunday in March and third Saturday in May to December 31. S-4 and C-2; none between 43-60 cm, not more than 1 greater than 60 cm.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Perch, Yellow'), NULL, 0, NULL, NULL, NULL, NULL, 50, 25, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Yellow perch. Open all year. S-50 and C-25.')
;
GO

------------------------------ FMZ 12 ------------------------------
DECLARE @z int = 12; DECLARE @link nvarchar(255) = N'https://www.ontario.ca/document/ontario-fishing-regulations-summary/fisheries-management-zone-12';
DELETE FROM dbo.regulations WHERE state='ON' AND zone_id=@z AND Lake_id IS NULL AND reg_year=2026;
INSERT INTO dbo.regulations
    (state, zone_id, Lake_id, fish_id, chain, resident_type, regulations_date_start, regulations_start, regulations_date_end, regulations_end, regulations_sport, regulations_consr, min_length_cm, slot_min_cm, slot_max_cm, slot_over_limit, method_flags, regulations_code, regulations_link, regulations_text)
VALUES
('ON', @z, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, 5, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Aggregate limit for all trout and salmon (including splake): S-5 and C-2 total daily catch and possession for all species combined.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Salmon, Atlantic'), NULL, 0, NULL, N'Friday before fourth Saturday in April', '2026-09-30', NULL, 1, 0, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Atlantic salmon. Friday before fourth Saturday in April to September 30. S-1 and C-0.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Trout, Brook'), NULL, 0, NULL, N'Friday before fourth Saturday in April', '2026-09-30', NULL, 5, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Brook trout. Friday before fourth Saturday in April to September 30. S-5 and C-2.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Trout, Brown'), NULL, 0, NULL, N'Friday before fourth Saturday in April', '2026-09-30', NULL, 5, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Brown and rainbow trout. Friday before fourth Saturday in April to September 30. S-5 and C-2.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Trout, Rainbow'), NULL, 0, NULL, N'Friday before fourth Saturday in April', '2026-09-30', NULL, 5, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Brown and rainbow trout. Friday before fourth Saturday in April to September 30. S-5 and C-2.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Catfish, Channel'), NULL, 0, NULL, NULL, NULL, NULL, 12, 6, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Channel catfish. Open all year. S-12 and C-6.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Crappie, Black'), NULL, 0, NULL, NULL, NULL, NULL, 30, 10, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Crappie. Open all year. S-30 and C-10.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Sturgeon, Lake'), NULL, 0, NULL, NULL, NULL, NULL, 0, 0, NULL, NULL, NULL, NULL, NULL, 1, @link, N'Lake sturgeon. Closed all year.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Trout, Lake'), NULL, 0, NULL, N'Friday before fourth Saturday in April', '2026-09-30', NULL, 2, 1, 45, NULL, NULL, NULL, NULL, 8, @link, N'Lake trout and splake. Friday before fourth Saturday in April to September 30. S-2 and C-1; must be greater than 45 cm.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Splake'), NULL, 0, NULL, N'Friday before fourth Saturday in April', '2026-09-30', NULL, 2, 1, 45, NULL, NULL, NULL, NULL, 8, @link, N'Lake trout and splake. Friday before fourth Saturday in April to September 30. S-2 and C-1; must be greater than 45 cm.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Whitefish, Lake'), NULL, 0, NULL, NULL, NULL, NULL, 12, 6, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Lake whitefish. Open all year. S-12 and C-6.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Bass, Smallmouth'), (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Bass, Largemouth'), 0, NULL, N'Friday before fourth Saturday in June', '2026-11-30', NULL, 6, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Largemouth and smallmouth bass combined. Friday before fourth Saturday in June to November 30. S-6 and C-2.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Muskellunge'), NULL, 0, NULL, N'Friday before third Saturday in June', '2026-12-15', NULL, 1, 0, 137, NULL, NULL, NULL, NULL, 8, @link, N'Muskellunge. Friday before third Saturday in June to December 15. S-1; must be greater than 137 cm, and C-0.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Pike, Northern'), NULL, 0, NULL, NULL, NULL, NULL, 6, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Northern pike. January 1 to March 31 and Friday before third Saturday in May to December 31. S-6 and C-2.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Sunfish, Bluegill'), NULL, 0, NULL, NULL, NULL, NULL, 999, 999, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Sunfish (bluegill, pumpkinseed and other sunfish). Open all year. No limit.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Walleye'), (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Sauger'), 0, NULL, NULL, NULL, NULL, 5, 2, NULL, NULL, 40, NULL, NULL, 8, @link, N'Walleye and sauger combined. January 1 to March 31 and Friday before third Saturday in May to December 31. S-5 and C-2; must be less than 40 cm from March 1 to June 15.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Perch, Yellow'), NULL, 0, NULL, NULL, NULL, NULL, 50, 25, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Yellow perch. Open all year. S-50 and C-25.')
;
GO

------------------------------ FMZ 13 ------------------------------
DECLARE @z int = 13; DECLARE @link nvarchar(255) = N'https://www.ontario.ca/document/ontario-fishing-regulations-summary/fisheries-management-zone-13';
DELETE FROM dbo.regulations WHERE state='ON' AND zone_id=@z AND Lake_id IS NULL AND reg_year=2026;
INSERT INTO dbo.regulations
    (state, zone_id, Lake_id, fish_id, chain, resident_type, regulations_date_start, regulations_start, regulations_date_end, regulations_end, regulations_sport, regulations_consr, min_length_cm, slot_min_cm, slot_max_cm, slot_over_limit, method_flags, regulations_code, regulations_link, regulations_text)
VALUES
('ON', @z, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, 5, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Aggregate limit for all trout and salmon (including splake): S-5 and C-2 total daily catch and possession for all species combined.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Salmon, Atlantic'), NULL, 0, NULL, NULL, NULL, NULL, 1, 0, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Atlantic salmon. Open all year. S-1 and C-0.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Trout, Brown'), NULL, 0, NULL, NULL, NULL, NULL, 5, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Brown trout. Open all year. S-5 and C-2.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Catfish, Channel'), NULL, 0, NULL, NULL, NULL, NULL, 12, 6, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Channel catfish. Open all year. S-12 and C-6.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Crappie, Black'), NULL, 0, NULL, NULL, NULL, NULL, 30, 10, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Crappie. Open all year. S-30 and C-10.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Sturgeon, Lake'), NULL, 0, NULL, NULL, NULL, NULL, 0, 0, NULL, NULL, NULL, NULL, NULL, 1, @link, N'Lake sturgeon. Closed all year.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Trout, Lake'), NULL, 0, '2026-01-01', NULL, '2026-09-30', NULL, 2, 1, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Lake trout. January 1 to September 30 and December 1 to December 31. S-2 and C-1.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Whitefish, Lake'), NULL, 0, NULL, NULL, NULL, NULL, 12, 6, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Lake whitefish. Open all year. S-12 and C-6.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Bass, Smallmouth'), (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Bass, Largemouth'), 0, NULL, N'fourth Saturday in June', '2026-11-30', NULL, 6, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Largemouth and smallmouth bass combined. Fourth Saturday in June to November 30. S-6 and C-2.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Muskellunge'), NULL, 0, NULL, N'third Saturday in June', '2026-12-15', NULL, 1, 0, 102, NULL, NULL, NULL, NULL, 8, @link, N'Muskellunge. Third Saturday in June to December 15. S-1; must be greater than 102 cm, and C-0.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Pike, Northern'), NULL, 0, NULL, NULL, NULL, NULL, 4, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Northern pike. Open all year. S-4 and C-2.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Salmon, Chinook'), NULL, 0, NULL, NULL, NULL, NULL, 5, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Pacific salmon (Chinook, Coho and other Pacific salmon). Open all year. S-5 and C-2.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Trout, Rainbow'), NULL, 0, NULL, NULL, NULL, NULL, 2, 1, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Rainbow trout. Open all year. S-2 and C-1.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Sunfish, Bluegill'), NULL, 0, NULL, NULL, NULL, NULL, 50, 25, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Sunfish (bluegill, pumpkinseed and other sunfish). Open all year. S-50 and C-25.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Walleye'), (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Sauger'), 0, NULL, NULL, NULL, NULL, 6, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Walleye and sauger combined. Open all year. S-6 and C-2.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Perch, Yellow'), NULL, 0, NULL, NULL, NULL, NULL, 50, 25, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Yellow perch. Open all year. S-50 and C-25.')
;
GO

------------------------------ FMZ 14 ------------------------------
DECLARE @z int = 14; DECLARE @link nvarchar(255) = N'https://www.ontario.ca/document/ontario-fishing-regulations-summary/fisheries-management-zone-14';
DELETE FROM dbo.regulations WHERE state='ON' AND zone_id=@z AND Lake_id IS NULL AND reg_year=2026;
INSERT INTO dbo.regulations
    (state, zone_id, Lake_id, fish_id, chain, resident_type, regulations_date_start, regulations_start, regulations_date_end, regulations_end, regulations_sport, regulations_consr, min_length_cm, slot_min_cm, slot_max_cm, slot_over_limit, method_flags, regulations_code, regulations_link, regulations_text)
VALUES
('ON', @z, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, 5, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Aggregate limit for all trout and salmon (including splake): S-5 and C-2 total daily catch and possession for all species combined.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Salmon, Atlantic'), NULL, 0, NULL, NULL, NULL, NULL, 1, 0, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Atlantic salmon. Open all year. S-1 and C-0.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Trout, Brown'), NULL, 0, NULL, NULL, NULL, NULL, 5, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Brown trout. Open all year. S-5 and C-2.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Catfish, Channel'), NULL, 0, NULL, NULL, NULL, NULL, 12, 6, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Channel catfish. Open all year. S-12 and C-6.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Crappie, Black'), NULL, 0, NULL, NULL, NULL, NULL, 30, 10, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Crappie. Open all year. S-30 and C-10.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Herring, Lake'), NULL, 0, NULL, NULL, NULL, NULL, 25, 12, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Lake herring (cisco). Open all year. S-25 and C-12.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Sturgeon, Lake'), NULL, 0, NULL, NULL, NULL, NULL, 0, 0, NULL, NULL, NULL, NULL, NULL, 1, @link, N'Lake sturgeon. Closed all year.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Trout, Lake'), NULL, 0, '2026-01-01', NULL, '2026-09-30', NULL, 2, 1, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Lake trout. January 1 to September 30 and December 1 to December 31. S-2 and C-1.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Whitefish, Lake'), NULL, 0, NULL, NULL, NULL, NULL, 12, 6, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Lake whitefish. Open all year. S-12 and C-6.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Bass, Smallmouth'), (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Bass, Largemouth'), 0, NULL, N'fourth Saturday in June', '2026-11-30', NULL, 3, 1, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Largemouth and smallmouth bass combined. Fourth Saturday in June to November 30. S-3 and C-1.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Muskellunge'), NULL, 0, NULL, N'third Saturday in June', '2026-12-15', NULL, 1, 0, 137, NULL, NULL, NULL, NULL, 8, @link, N'Muskellunge. Third Saturday in June to December 15. S-1; must be greater than 137 cm, and C-0.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Pike, Northern'), NULL, 0, '2026-01-01', NULL, '2026-03-01', NULL, 2, 1, NULL, NULL, 86, 1, NULL, 8, @link, N'Northern pike. January 1 to March 1 and May 1 to December 31. S-2; in one day, possession limit of 4, not more than 1 greater than 86 cm, and C-1; in one day, possession limit of 2, not more than 1 greater than 86 cm.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Salmon, Chinook'), NULL, 0, NULL, NULL, NULL, NULL, 5, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Pacific salmon (Chinook, Coho and other Pacific salmon). Open all year. S-5 and C-2.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Trout, Rainbow'), NULL, 0, NULL, NULL, NULL, NULL, 2, 1, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Rainbow trout. Open all year. S-2 and C-1.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Sunfish, Bluegill'), NULL, 0, NULL, NULL, NULL, NULL, 50, 25, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Sunfish (bluegill, pumpkinseed and other sunfish). Open all year. S-50 and C-25.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Walleye'), (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Sauger'), 0, '2026-01-01', NULL, '2026-03-01', NULL, 2, 1, NULL, 41, 56, 1, NULL, 8, @link, N'Walleye and sauger combined. January 1 to March 1 and May 1 to December 31. S-2; in one day, possession limit of 4, none between 41-56 cm, not more than 1 greater than 56 cm, and C-1; in one day, possession limit of 2, none between 41-56 cm, not more than 1 greater than 56 cm.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Perch, Yellow'), NULL, 0, NULL, NULL, NULL, NULL, 25, 12, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Yellow perch. Open all year. S-25; in one day, possession limit of 50, and C-12; in one day, possession limit of 25.')
;
GO

------------------------------ FMZ 15 ------------------------------
DECLARE @z int = 15; DECLARE @link nvarchar(255) = N'https://www.ontario.ca/document/ontario-fishing-regulations-summary/fisheries-management-zone-15';
DELETE FROM dbo.regulations WHERE state='ON' AND zone_id=@z AND Lake_id IS NULL AND reg_year=2026;
INSERT INTO dbo.regulations
    (state, zone_id, Lake_id, fish_id, chain, resident_type, regulations_date_start, regulations_start, regulations_date_end, regulations_end, regulations_sport, regulations_consr, min_length_cm, slot_min_cm, slot_max_cm, slot_over_limit, method_flags, regulations_code, regulations_link, regulations_text)
VALUES
('ON', @z, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, 5, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Aggregate limit for all trout and salmon (including splake): S-5 and C-2 total daily catch and possession for all species combined.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Salmon, Atlantic'), NULL, 0, NULL, NULL, NULL, NULL, 0, 0, NULL, NULL, NULL, NULL, NULL, 1, @link, N'Atlantic salmon. Closed all year.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Trout, Brook'), NULL, 0, '2026-01-01', NULL, '2026-09-30', NULL, 5, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Brook trout. January 1 to September 30. S-5 and C-2.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Trout, Brown'), NULL, 0, NULL, NULL, NULL, NULL, 5, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Brown trout. Open all year. S-5 and C-2.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Catfish, Channel'), NULL, 0, NULL, NULL, NULL, NULL, 12, 6, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Channel catfish. Open all year. S-12 and C-6.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Crappie, Black'), NULL, 0, NULL, NULL, NULL, NULL, 30, 10, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Crappie. Open all year. S-30 and C-10.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Sturgeon, Lake'), NULL, 0, NULL, NULL, NULL, NULL, 0, 0, NULL, NULL, NULL, NULL, NULL, 1, @link, N'Lake sturgeon. Closed all year.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Trout, Lake'), NULL, 0, '2026-01-01', NULL, '2026-09-30', NULL, 2, 1, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Lake trout. January 1 to September 30. S-2 and C-1.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Whitefish, Lake'), NULL, 0, NULL, NULL, NULL, NULL, 12, 6, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Lake whitefish. Open all year. S-12 and C-6.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Bass, Smallmouth'), (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Bass, Largemouth'), 0, NULL, N'fourth Saturday in June', '2026-11-30', NULL, 6, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Largemouth and smallmouth bass combined. Fourth Saturday in June to November 30. S-6 and C-2.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Muskellunge'), NULL, 0, NULL, N'first Saturday in June', '2026-12-15', NULL, 1, 0, 91, NULL, NULL, NULL, NULL, 8, @link, N'Muskellunge. First Saturday in June to December 15. S-1; must be greater than 91 cm, and C-0.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Pike, Northern'), NULL, 0, NULL, NULL, NULL, NULL, 6, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Northern pike. January 1 to March 31 and third Saturday in May to December 31. S-6 and C-2.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Salmon, Chinook'), NULL, 0, NULL, NULL, NULL, NULL, 5, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Pacific salmon (Chinook, Coho and other Pacific salmon). Open all year. S-5 and C-2.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Trout, Rainbow'), NULL, 0, NULL, NULL, NULL, NULL, 5, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Rainbow trout. Open all year. S-5 and C-2.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Splake'), NULL, 0, NULL, NULL, NULL, NULL, 5, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Splake. Open all year. S-5 and C-2.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Sunfish, Bluegill'), NULL, 0, NULL, NULL, NULL, NULL, 50, 25, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Sunfish (bluegill, pumpkinseed and other sunfish). Open all year. S-50 and C-25.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Walleye'), (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Sauger'), 0, NULL, NULL, NULL, NULL, 4, 2, NULL, NULL, 46, 1, NULL, 8, @link, N'Walleye and sauger combined. January 1 to March 15 and third Saturday in May to December 31. S-4 and C-2; not more than 1 greater than 46 cm.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Perch, Yellow'), NULL, 0, NULL, NULL, NULL, NULL, 50, 25, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Yellow perch. Open all year. S-50 and C-25.')
;
GO

------------------------------ FMZ 16 ------------------------------
DECLARE @z int = 16; DECLARE @link nvarchar(255) = N'https://www.ontario.ca/document/ontario-fishing-regulations-summary/fisheries-management-zone-16';
DELETE FROM dbo.regulations WHERE state='ON' AND zone_id=@z AND Lake_id IS NULL AND reg_year=2026;
INSERT INTO dbo.regulations
    (state, zone_id, Lake_id, fish_id, chain, resident_type, regulations_date_start, regulations_start, regulations_date_end, regulations_end, regulations_sport, regulations_consr, min_length_cm, slot_min_cm, slot_max_cm, slot_over_limit, method_flags, regulations_code, regulations_link, regulations_text)
VALUES
('ON', @z, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, 5, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Aggregate limit for all trout and salmon (including splake): S-5 and C-2 total daily catch and possession for all species combined.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Salmon, Atlantic'), NULL, 0, NULL, N'fourth Saturday in April', '2026-09-30', NULL, 0, 0, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Atlantic salmon. Fourth Saturday in April to September 30. S-0 and C-0.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Trout, Brook'), NULL, 0, NULL, N'fourth Saturday in April', '2026-09-30', NULL, 5, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Brook trout. Fourth Saturday in April to September 30. S-5 and C-2.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Trout, Brown'), NULL, 0, NULL, N'fourth Saturday in April', '2026-09-30', NULL, 5, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Brown trout. Fourth Saturday in April to September 30. S-5 and C-2.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Trout, Rainbow'), NULL, 0, NULL, N'fourth Saturday in April', '2026-09-30', NULL, 2, 1, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Rainbow trout. Fourth Saturday in April to September 30. S-2 and C-1.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Splake'), NULL, 0, NULL, NULL, NULL, NULL, 5, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Splake. Open all year. S-5 and C-2.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Trout, Lake'), NULL, 0, '2026-01-01', NULL, '2026-09-30', NULL, 2, 1, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Lake trout. January 1 to September 30. S-2 and C-1.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Salmon, Chinook'), NULL, 0, NULL, N'fourth Saturday in April', '2026-09-30', NULL, 5, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Pacific salmon (Chinook, Coho and other Pacific salmon). Fourth Saturday in April to September 30. S-5 and C-2.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Walleye'), (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Sauger'), 0, NULL, NULL, NULL, NULL, 4, 2, NULL, NULL, 46, 1, NULL, 8, @link, N'Walleye and sauger combined. January 1 to March 15 and second Saturday in May to December 31. S-4 and C-2; not more than 1 greater than 46 cm.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Pike, Northern'), NULL, 0, NULL, NULL, NULL, NULL, 6, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Northern pike. January 1 to March 31 and second Saturday in May to December 31. S-6 and C-2.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Bass, Smallmouth'), (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Bass, Largemouth'), 0, NULL, N'fourth Saturday in June', '2026-11-30', NULL, 6, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Largemouth and smallmouth bass combined. Fourth Saturday in June to November 30. S-6 and C-2.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Muskellunge'), NULL, 0, NULL, N'first Saturday in June', '2026-12-15', NULL, 1, 0, 91, NULL, NULL, NULL, NULL, 8, @link, N'Muskellunge. First Saturday in June to December 15. S-1; must be greater than 91 cm, and C-0.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Whitefish, Lake'), NULL, 0, NULL, NULL, NULL, NULL, 12, 6, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Lake whitefish. Open all year. S-12 and C-6.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Perch, Yellow'), NULL, 0, NULL, NULL, NULL, NULL, 50, 25, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Yellow perch. Open all year. S-50 and C-25.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Sunfish, Bluegill'), NULL, 0, NULL, NULL, NULL, NULL, 50, 25, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Sunfish (bluegill, pumpkinseed and other sunfish). Open all year. S-50 and C-25.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Crappie, Black'), NULL, 0, NULL, NULL, NULL, NULL, 30, 10, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Crappie. Open all year. S-30 and C-10.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Catfish, Channel'), NULL, 0, NULL, NULL, NULL, NULL, 12, 6, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Channel catfish. Open all year. S-12 and C-6.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Sturgeon, Lake'), NULL, 0, NULL, NULL, NULL, NULL, 0, 0, NULL, NULL, NULL, NULL, NULL, 1, @link, N'Lake sturgeon. Closed all year.')
;
GO

------------------------------ FMZ 17 ------------------------------
DECLARE @z int = 17; DECLARE @link nvarchar(255) = N'https://www.ontario.ca/document/ontario-fishing-regulations-summary/fisheries-management-zone-17';
DELETE FROM dbo.regulations WHERE state='ON' AND zone_id=@z AND Lake_id IS NULL AND reg_year=2026;
INSERT INTO dbo.regulations
    (state, zone_id, Lake_id, fish_id, chain, resident_type, regulations_date_start, regulations_start, regulations_date_end, regulations_end, regulations_sport, regulations_consr, min_length_cm, slot_min_cm, slot_max_cm, slot_over_limit, method_flags, regulations_code, regulations_link, regulations_text)
VALUES
('ON', @z, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, 5, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Aggregate limit for all trout and salmon (including splake): S-5 and C-2 total daily catch and possession for all species combined.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Salmon, Atlantic'), NULL, 0, NULL, N'fourth Saturday in April', '2026-09-30', NULL, 0, 0, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Atlantic salmon. Fourth Saturday in April to September 30. S-0 and C-0.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Trout, Brook'), NULL, 0, NULL, N'fourth Saturday in April', '2026-09-30', NULL, 2, 1, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Brook trout. Fourth Saturday in April to September 30. S-2 and C-1.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Trout, Brown'), NULL, 0, NULL, N'fourth Saturday in April', '2026-09-30', NULL, 5, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Brown trout. Fourth Saturday in April to September 30. S-5 and C-2.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Trout, Rainbow'), NULL, 0, NULL, N'fourth Saturday in April', '2026-09-30', NULL, 2, 1, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Rainbow trout. Fourth Saturday in April to September 30. S-2 and C-1.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Salmon, Chinook'), NULL, 0, NULL, N'fourth Saturday in April', '2026-09-30', NULL, 5, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Pacific salmon (Chinook, Coho and other Pacific salmon). Fourth Saturday in April to September 30. S-5 and C-2.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Trout, Lake'), NULL, 0, NULL, N'fourth Saturday in April', '2026-09-30', NULL, 3, 1, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Lake trout. Fourth Saturday in April to September 30. S-3 and C-1.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Pike, Northern'), NULL, 0, NULL, NULL, NULL, NULL, 6, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Northern pike. Open all year. S-6 and C-2.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Walleye'), (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Sauger'), 0, NULL, N'second Saturday in May', '2026-11-15', NULL, 4, 1, NULL, 35, 50, NULL, NULL, 8, @link, N'Walleye and sauger combined. Second Saturday in May to November 15. S-4 and C-1; must be between 35-50 cm.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Bass, Smallmouth'), (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Bass, Largemouth'), 0, NULL, N'third Saturday in June', '2026-12-15', NULL, 6, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Largemouth and smallmouth bass combined. Third Saturday in June to December 15. S-6 and C-2.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Muskellunge'), NULL, 0, NULL, N'first Saturday in June', '2026-12-15', NULL, 1, 0, 112, NULL, NULL, NULL, NULL, 8, @link, N'Muskellunge. First Saturday in June to December 15. S-1; must be greater than 112 cm, and C-0.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Whitefish, Lake'), NULL, 0, NULL, N'fourth Saturday in April', '2026-11-15', NULL, 12, 6, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Lake whitefish. Fourth Saturday in April to November 15. S-12 and C-6.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Perch, Yellow'), NULL, 0, NULL, NULL, NULL, NULL, 50, 25, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Yellow perch. Open all year. S-50 and C-25.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Crappie, Black'), NULL, 0, NULL, NULL, NULL, NULL, 30, 10, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Crappie. Open all year. S-30 and C-10.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Sunfish, Bluegill'), NULL, 0, NULL, NULL, NULL, NULL, 300, 15, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Sunfish (bluegill, pumpkinseed and other sunfish). Open all year. S-300; only 30 may be greater than 18 cm, and C-15.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Catfish, Channel'), NULL, 0, NULL, N'fourth Saturday in April', '2026-11-15', NULL, 12, 6, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Channel catfish. Fourth Saturday in April to November 15. S-12 and C-6.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Sturgeon, Lake'), NULL, 0, NULL, NULL, NULL, NULL, 0, 0, NULL, NULL, NULL, NULL, NULL, 1, @link, N'Lake sturgeon. Closed all year.')
;
GO

------------------------------ FMZ 18 ------------------------------
DECLARE @z int = 18; DECLARE @link nvarchar(255) = N'https://www.ontario.ca/document/ontario-fishing-regulations-summary/fisheries-management-zone-18';
DELETE FROM dbo.regulations WHERE state='ON' AND zone_id=@z AND Lake_id IS NULL AND reg_year=2026;
INSERT INTO dbo.regulations
    (state, zone_id, Lake_id, fish_id, chain, resident_type, regulations_date_start, regulations_start, regulations_date_end, regulations_end, regulations_sport, regulations_consr, min_length_cm, slot_min_cm, slot_max_cm, slot_over_limit, method_flags, regulations_code, regulations_link, regulations_text)
VALUES
('ON', @z, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, 5, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Aggregate limit for all trout and salmon (including splake): S-5 and C-2 total daily catch and possession for all species combined.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Salmon, Atlantic'), NULL, 0, NULL, NULL, NULL, NULL, 0, 0, NULL, NULL, NULL, NULL, NULL, 1, @link, N'Atlantic salmon. Closed all year.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Trout, Brook'), NULL, 0, NULL, NULL, NULL, NULL, 5, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Brook trout. Open all year. S-5 and C-2.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Trout, Brown'), NULL, 0, NULL, NULL, NULL, NULL, 5, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Brown trout. Open all year. S-5 and C-2.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Catfish, Channel'), NULL, 0, NULL, NULL, NULL, NULL, 12, 6, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Channel catfish. Open all year. S-12 and C-6.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Crappie, Black'), NULL, 0, NULL, NULL, NULL, NULL, 30, 10, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Crappie. Open all year. S-30 and C-10.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Sturgeon, Lake'), NULL, 0, NULL, NULL, NULL, NULL, 0, 0, NULL, NULL, NULL, NULL, NULL, 1, @link, N'Lake sturgeon. Closed all year.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Trout, Lake'), NULL, 0, NULL, N'fourth Saturday in May', '2026-09-08', NULL, 2, 1, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Lake trout. Fourth Saturday in May to September 8. S-2 and C-1.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Whitefish, Lake'), NULL, 0, NULL, NULL, NULL, NULL, 12, 6, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Lake whitefish. Open all year. S-12 and C-6.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Bass, Smallmouth'), (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Bass, Largemouth'), 0, NULL, N'third Saturday in June', '2026-12-15', NULL, 6, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Largemouth and smallmouth bass combined. Third Saturday in June to December 15. S-6 and C-2.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Muskellunge'), NULL, 0, NULL, N'first Saturday in June', '2026-12-15', NULL, 1, 0, 91, NULL, NULL, NULL, NULL, 8, @link, N'Muskellunge. First Saturday in June to December 15. S-1; must be greater than 91 cm, and C-0.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Pike, Northern'), NULL, 0, NULL, NULL, NULL, NULL, 6, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Northern pike. January 1 to March 31 and second Saturday in May to December 31. S-6 and C-2.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Salmon, Chinook'), NULL, 0, NULL, NULL, NULL, NULL, 5, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Pacific salmon (Chinook, Coho and other Pacific salmon). Open all year. S-5 and C-2.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Trout, Rainbow'), NULL, 0, NULL, NULL, NULL, NULL, 5, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Rainbow trout. Open all year. S-5 and C-2.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Splake'), NULL, 0, NULL, NULL, NULL, NULL, 5, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Splake. Open all year. S-5 and C-2.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Sunfish, Bluegill'), NULL, 0, NULL, NULL, NULL, NULL, 300, 15, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Sunfish (bluegill, pumpkinseed and other sunfish). Open all year. S-300; only 30 may be greater than 18 cm, and C-15.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Walleye'), (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Sauger'), 0, '2026-01-01', NULL, '2026-03-01', NULL, 4, 2, NULL, 40, 50, NULL, NULL, 8, @link, N'Walleye and sauger combined. January 1 to March 1 and second Saturday in May to December 31. S-4 and C-2; must be between 40-50 cm.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Perch, Yellow'), NULL, 0, NULL, NULL, NULL, NULL, 50, 25, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Yellow perch. Open all year. S-50 and C-25.')
;
GO

------------------------------ FMZ 19 ------------------------------
DECLARE @z int = 19; DECLARE @link nvarchar(255) = N'https://www.ontario.ca/document/ontario-fishing-regulations-summary/fisheries-management-zone-19';
DELETE FROM dbo.regulations WHERE state='ON' AND zone_id=@z AND Lake_id IS NULL AND reg_year=2026;
INSERT INTO dbo.regulations
    (state, zone_id, Lake_id, fish_id, chain, resident_type, regulations_date_start, regulations_start, regulations_date_end, regulations_end, regulations_sport, regulations_consr, min_length_cm, slot_min_cm, slot_max_cm, slot_over_limit, method_flags, regulations_code, regulations_link, regulations_text)
VALUES
('ON', @z, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, 5, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Aggregate limit for all trout and salmon (including splake): S-5 and C-2 total daily catch and possession for all species combined.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Salmon, Atlantic'), NULL, 0, NULL, NULL, NULL, NULL, 1, 0, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Atlantic salmon. Open all year. S-1 and C-0.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Trout, Brown'), NULL, 0, NULL, NULL, NULL, NULL, 5, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Brown trout. Open all year. S-5 and C-2.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Catfish, Channel'), NULL, 0, NULL, NULL, NULL, NULL, 12, 6, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Channel catfish. Open all year. S-12 and C-6.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Crappie, Black'), NULL, 0, NULL, NULL, NULL, NULL, 30, 10, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Crappie. Open all year. S-30 and C-10.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Sturgeon, Lake'), NULL, 0, NULL, NULL, NULL, NULL, 0, 0, NULL, NULL, NULL, NULL, NULL, 1, @link, N'Lake sturgeon. Closed all year.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Trout, Lake'), NULL, 0, '2026-01-01', NULL, '2026-09-30', NULL, 3, 1, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Lake trout. January 1 to September 30 and December 1 to December 31. S-3 and C-1.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Whitefish, Lake'), NULL, 0, NULL, NULL, NULL, NULL, 12, 6, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Lake whitefish. Open all year. S-12 and C-6.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Bass, Smallmouth'), (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Bass, Largemouth'), 0, NULL, N'fourth Saturday in June', '2026-11-30', NULL, 6, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Largemouth and smallmouth bass combined. Fourth Saturday in June to November 30. S-6 and C-2.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Muskellunge'), NULL, 0, NULL, N'first Saturday in June', '2026-12-15', NULL, 1, 0, 112, NULL, NULL, NULL, NULL, 8, @link, N'Muskellunge. First Saturday in June to December 15. S-1; must be greater than 112 cm, and C-0.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Pike, Northern'), NULL, 0, NULL, NULL, NULL, NULL, 6, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Northern pike. Open all year. S-6 and C-2.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Salmon, Chinook'), NULL, 0, NULL, NULL, NULL, NULL, 5, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Pacific salmon (Chinook, Coho and other Pacific salmon). Open all year. S-5 and C-2.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Trout, Rainbow'), NULL, 0, NULL, NULL, NULL, NULL, 5, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Rainbow trout. Open all year. S-5 and C-2.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Sunfish, Bluegill'), NULL, 0, NULL, NULL, NULL, NULL, 100, 50, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Sunfish (bluegill, pumpkinseed and other sunfish). Open all year. S-100 and C-50.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Walleye'), (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Sauger'), 0, NULL, NULL, NULL, NULL, 6, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Walleye and sauger combined. Open all year. S-6 and C-2.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Perch, Yellow'), NULL, 0, NULL, NULL, NULL, NULL, 50, 25, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Yellow perch. Open all year. S-50; in one day, possession limit of 100, and C-25; in one day, possession limit of 50.')
;
GO

------------------------------ FMZ 20 ------------------------------
DECLARE @z int = 20; DECLARE @link nvarchar(255) = N'https://www.ontario.ca/document/ontario-fishing-regulations-summary/fisheries-management-zone-20';
DELETE FROM dbo.regulations WHERE state='ON' AND zone_id=@z AND Lake_id IS NULL AND reg_year=2026;
INSERT INTO dbo.regulations
    (state, zone_id, Lake_id, fish_id, chain, resident_type, regulations_date_start, regulations_start, regulations_date_end, regulations_end, regulations_sport, regulations_consr, min_length_cm, slot_min_cm, slot_max_cm, slot_over_limit, method_flags, regulations_code, regulations_link, regulations_text)
VALUES
('ON', @z, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, 5, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Aggregate limit for all trout and salmon (including splake): S-5 and C-2 total daily catch and possession for all species combined.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Salmon, Atlantic'), NULL, 0, NULL, NULL, NULL, NULL, 1, 0, 63, NULL, NULL, NULL, NULL, 8, @link, N'Atlantic salmon. Open all year. S-1 and C-0; must be greater than 63 cm.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Trout, Brown'), NULL, 0, NULL, NULL, NULL, NULL, 5, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Brown trout. Open all year. S-5 and C-2.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Catfish, Channel'), NULL, 0, NULL, NULL, NULL, NULL, 12, 6, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Channel catfish. Open all year. S-12 and C-6.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Crappie, Black'), NULL, 0, NULL, NULL, NULL, NULL, 30, 10, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Crappie. Open all year. S-30 and C-10.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Sturgeon, Lake'), NULL, 0, NULL, NULL, NULL, NULL, 0, 0, NULL, NULL, NULL, NULL, NULL, 1, @link, N'Lake sturgeon. Closed all year.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Trout, Lake'), NULL, 0, '2026-01-01', NULL, '2026-09-30', NULL, 3, 1, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Lake trout. January 1 to September 30 and December 1 to December 31. S-3 and C-1.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Whitefish, Lake'), NULL, 0, NULL, NULL, NULL, NULL, 12, 6, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Lake whitefish. Open all year. S-12 and C-6.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Bass, Largemouth'), NULL, 0, '2026-01-01', NULL, '2026-05-10', NULL, 0, 0, NULL, NULL, NULL, NULL, 1, 8, @link, N'Largemouth bass. Early season January 1 to May 10: catch-and-release only, S-0 and C-0. Regular season third Saturday in June to December 31: S-6 and C-2.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Bass, Smallmouth'), NULL, 0, '2026-01-01', NULL, '2026-05-10', NULL, 0, 0, NULL, NULL, NULL, NULL, 1, 8, @link, N'Smallmouth bass. Early season January 1 to May 10: catch-and-release only, S-0 and C-0. Regular season first Saturday in July to December 31: S-6 and C-2.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Muskellunge'), NULL, 0, NULL, N'third Saturday in June', '2026-12-15', NULL, 1, 0, 137, NULL, NULL, NULL, NULL, 8, @link, N'Muskellunge. Third Saturday in June to December 15. S-1; must be greater than 137 cm, and C-0.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Pike, Northern'), NULL, 0, NULL, NULL, NULL, NULL, 6, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Northern pike. January 1 to March 31 and first Saturday in May to December 31. S-6 and C-2.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Salmon, Chinook'), NULL, 0, NULL, NULL, NULL, NULL, 5, 2, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Pacific salmon (Chinook, Coho and other Pacific salmon). Open all year. S-5 and C-2.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Trout, Rainbow'), NULL, 0, NULL, NULL, NULL, NULL, 2, 1, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Rainbow trout. Open all year. S-2 and C-1.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Sunfish, Bluegill'), NULL, 0, NULL, NULL, NULL, NULL, 100, 50, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Sunfish (bluegill, pumpkinseed and other sunfish). Open all year. S-100 and C-50.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Walleye'), (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Sauger'), 0, '2026-01-01', NULL, '2026-03-01', NULL, 4, 2, NULL, NULL, 63, 1, NULL, 8, @link, N'Walleye and sauger combined. January 1 to March 1 and first Saturday in May to December 31. S-4 and C-2; not more than 1 greater than 63 cm.'),
('ON', @z, NULL, (SELECT fish_id FROM dbo.fish WHERE fish_name=N'Perch, Yellow'), NULL, 0, NULL, NULL, NULL, NULL, 50, 25, NULL, NULL, NULL, NULL, NULL, 8, @link, N'Yellow perch. Open all year. S-50 and C-25.')
;
GO

