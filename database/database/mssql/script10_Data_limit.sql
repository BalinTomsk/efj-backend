------------------------------------------------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------------------------------------------
-- province default limits:
DECLARE @reglink sysname ='https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf'
INSERT INTO regulations (state, chain, fish_id, regulations_sport, regulations_consr, regulations_sport_text, regulations_link) VALUES
     ('ON', NULL, 'a35109a0-63ba-4bf5-8a25-2e7e39b74f6e', 1, 1, 'Pacific Salmon - 5', @reglink)
    ,('ON', NULL, 'fcf58413-543e-4ad4-9ae4-6728bb62befe', 1, 1, NULL, @reglink)
    ,('ON', NULL, 'f124f917-d11f-4ed9-9b59-863d184cbfed', 5, 5, NULL, @reglink)
    ,('ON', NULL, '6dbf1306-dc10-421a-a29b-b260d540a0ae', 5, 5, NULL, @reglink)
    ,('ON', NULL, '969c00e3-1ed1-4845-bffc-a1dc51e2105d', 12, 12, NULL, @reglink)
    ,('ON', NULL, '5ab8a0ee-a5ca-43e6-b628-73e2bc12266e', 30, 30, NULL, @reglink)
    ,('ON', '5ab8a0ee-a5ca-43e6-b628-73e2bc12266e', '073cd69e-d9f4-4377-a746-b6f32cb9e3ba', 30, 30, NULL, @reglink)
    ,('ON', NULL, 'f3c65c73-f913-43b8-9f22-965ab095d13e', 3, 3, NULL, @reglink)
    ,('ON', NULL, 'e8003bda-f3ce-415d-834e-ff9b157b2da1', 3, 3, NULL, @reglink)
    ,('ON', NULL, '2038693f-d38c-43c8-b0ce-4e96b0f9af7e', 6, 6, NULL, @reglink)
    ,('ON', '2038693f-d38c-43c8-b0ce-4e96b0f9af7e', 'a85ebf22-4ab9-4a91-a14a-cef6c8e64d97', 6, 6, NULL, @reglink)
    ,('ON', NULL, '896837e4-3fe3-44c6-baee-5a490fbf64c8', 1, 1, NULL, @reglink)
    ,('ON', NULL, 'd07efe63-baf4-4dd1-9b1c-fe94c5860185', 6, 6, NULL, @reglink)
    ,('ON', NULL, 'b3a33573-8bc6-4803-b977-10f673aad711', 5, 5, NULL, @reglink)
    ,('ON', NULL, '19c45110-154d-477f-ba55-309be16e54ca', 5, 5, NULL, @reglink)
    ,('ON', NULL, '2cffb500-3e59-4120-9460-055856e9ac5c', 6, 6, NULL, @reglink)
    ,('ON', '2cffb500-3e59-4120-9460-055856e9ac5c', '8014674d-ca30-4e61-8fa2-4d80d94e5f45', 6, 6, NULL, @reglink)
    ,('ON', NULL, '2460a02d-cd68-435f-be2a-0f5aa1275dd4', 6, 6, NULL, @reglink)
GO
------------------------------------------------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Bowfin
EXEC sp_add_regulation 'ON', 10, 'Method: Bow and arrow during daylight hours only', 'May 1', 'July 31', NULL, NULL, NULL, 'D1814745-D6C3-4A95-8503-3C6DFB5B8B21'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
GO
EXEC sp_add_regulation 'ON', 13, 'Method: Bow and arrow during daylight hours only', 'May 1', 'July 31', NULL, NULL, NULL, 'D1814745-D6C3-4A95-8503-3C6DFB5B8B21'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
GO
EXEC sp_add_regulation 'ON', 14, 'Method: Bow and arrow during daylight hours only', 'May 1', 'July 31', NULL, NULL, NULL, 'D1814745-D6C3-4A95-8503-3C6DFB5B8B21'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
GO
EXEC sp_add_regulation 'ON', 19, 'Method: Bow and arrow during daylight hours only', 'May 1', 'July 31', NULL, NULL, NULL, 'D1814745-D6C3-4A95-8503-3C6DFB5B8B21'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
------------------------------------------------------------------------------------------------------------------------------------------------------------
-- common carp
EXEC sp_add_regulation 'ON', 5, '', 'May 1', 'July 31', NULL, NULL, NULL, '4f023204-cdaf-4fae-bf7f-e9319794e8ff'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
GO
EXEC sp_add_regulation 'ON', 6, '', 'May 1', 'July 31', NULL, NULL, NULL, '4f023204-cdaf-4fae-bf7f-e9319794e8ff'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
GO
EXEC sp_add_regulation 'ON', 9, '', 'May 1', 'July 31', NULL, NULL, NULL, '4f023204-cdaf-4fae-bf7f-e9319794e8ff'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
GO
EXEC sp_add_regulation 'ON', 10, '', 'May 1', 'July 31', NULL, NULL, NULL, '4f023204-cdaf-4fae-bf7f-e9319794e8ff'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
GO
EXEC sp_add_regulation 'ON', 12, '', 'May 1', 'July 31', NULL, NULL, NULL, '4f023204-cdaf-4fae-bf7f-e9319794e8ff'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
GO
EXEC sp_add_regulation 'ON', 13, '', 'May 1', 'July 31', NULL, NULL, NULL, '4f023204-cdaf-4fae-bf7f-e9319794e8ff'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
GO
EXEC sp_add_regulation 'ON', 14, '', 'May 1', 'July 31', NULL, NULL, NULL, '4f023204-cdaf-4fae-bf7f-e9319794e8ff'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
GO
EXEC sp_add_regulation 'ON', 15, 'Except Algonquin Park', 'May 1', 'July 31', NULL, NULL, NULL, '4f023204-cdaf-4fae-bf7f-e9319794e8ff'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
GO
EXEC sp_add_regulation 'ON', 16, '', 'May 1', 'July 31', NULL, NULL, NULL, '4f023204-cdaf-4fae-bf7f-e9319794e8ff'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
GO
EXEC sp_add_regulation 'ON', 18, '', 'May 1', 'July 31', NULL, NULL, NULL, '4f023204-cdaf-4fae-bf7f-e9319794e8ff'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
GO
EXEC sp_add_regulation 'ON', 19, '', 'May 1', 'July 31', NULL, NULL, NULL, '4f023204-cdaf-4fae-bf7f-e9319794e8ff'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
GO
EXEC sp_add_regulation 'ON', 20, '', 'May 1', 'July 31', NULL, NULL, NULL, '4f023204-cdaf-4fae-bf7f-e9319794e8ff'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
GO
EXEC sp_add_regulation 'ON', 17, 'Method: Bow and arrow, spear, and dip net during daylight hours only', 'Second Saturday in May', 'July 31', NULL, NULL, NULL, '4f023204-cdaf-4fae-bf7f-e9319794e8ff'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
GO
------------------------------------------------------------------------------------------------------------------------------------------------------------
EXEC sp_add_regulation 'ON', 1, 'Method: Dip net day or night', 'October 1', 'December 15', NULL, NULL, NULL, '76e514c4-01c3-4a57-8578-035a8cef63ad'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
GO
EXEC sp_add_regulation 'ON', 2, 'Method: Dip net day or night', 'October 1', 'December 15', NULL, NULL, NULL, '76e514c4-01c3-4a57-8578-035a8cef63ad'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
GO
EXEC sp_add_regulation 'ON', 3, 'Method: Dip net day or night', 'October 1', 'December 15', NULL, NULL, NULL, '76e514c4-01c3-4a57-8578-035a8cef63ad'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
GO
EXEC sp_add_regulation 'ON', 4, 'Method: Dip net day or night', 'October 1', 'December 15', NULL, NULL, NULL, '76e514c4-01c3-4a57-8578-035a8cef63ad'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
GO
EXEC sp_add_regulation 'ON', 5, 'Method: Dip net day or night', 'October 1', 'December 15', NULL, NULL, NULL, '76e514c4-01c3-4a57-8578-035a8cef63ad'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
GO
EXEC sp_add_regulation 'ON', 6, 'Method: Dip net day or night', 'October 1', 'December 15', NULL, NULL, NULL, '76e514c4-01c3-4a57-8578-035a8cef63ad'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
GO
EXEC sp_add_regulation 'ON', 7, 'Method: Dip net day or night', 'October 1', 'December 15', NULL, NULL, NULL, '76e514c4-01c3-4a57-8578-035a8cef63ad'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
GO
EXEC sp_add_regulation 'ON', 8, 'Method: Dip net day or night', 'October 1', 'December 15', NULL, NULL, NULL, '76e514c4-01c3-4a57-8578-035a8cef63ad'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
GO
EXEC sp_add_regulation 'ON', 10, 'Method: Dip net day or night', 'October 1', 'December 15', NULL, NULL, NULL, '76e514c4-01c3-4a57-8578-035a8cef63ad'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
GO
EXEC sp_add_regulation 'ON', 11, 'Method: Dip net day or night. Contact local district office for details', 'October 1', 'December 15', NULL, NULL, NULL, '76e514c4-01c3-4a57-8578-035a8cef63ad'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
GO
EXEC sp_add_regulation 'ON', 15, 'Method: Dip net day or night. Contact local district office for details', 'October 1', 'December 15', NULL, NULL, NULL, '76e514c4-01c3-4a57-8578-035a8cef63ad'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
GO
------------------------------------------------------------------------------------------------------------------------------------------------------------
--   White Sucker
EXEC sp_add_regulation 'ON', 1, 'Method: Bow and arrow, spear, and dip net during daylight hours only', 'March 1', 'May 31', NULL, NULL, NULL, '32975f54-4568-40ec-b2ae-a5dbc4088927'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
EXEC sp_add_regulation 'ON', 2, 'Method: Bow and arrow, spear, and dip net during daylight hours only', 'March 1', 'May 31', NULL, NULL, NULL, '32975f54-4568-40ec-b2ae-a5dbc4088927'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
EXEC sp_add_regulation 'ON', 3, 'Method: Bow and arrow, spear, and dip net during daylight hours only', 'March 1', 'May 31', NULL, NULL, NULL, '32975f54-4568-40ec-b2ae-a5dbc4088927'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
EXEC sp_add_regulation 'ON', 4, 'Method: Bow and arrow, spear, and dip net during daylight hours only', 'March 1', 'May 31', NULL, NULL, NULL, '32975f54-4568-40ec-b2ae-a5dbc4088927'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
EXEC sp_add_regulation 'ON', 5, 'Method: Bow and arrow, spear, and dip net during daylight hours only', 'March 1', 'May 31', NULL, NULL, NULL, '32975f54-4568-40ec-b2ae-a5dbc4088927'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
EXEC sp_add_regulation 'ON', 6, 'Method: Bow and arrow, spear, and dip net during daylight hours only', 'March 1', 'May 31', NULL, NULL, NULL, '32975f54-4568-40ec-b2ae-a5dbc4088927'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
EXEC sp_add_regulation 'ON', 7, 'Method: Bow and arrow, spear, and dip net during daylight hours only', 'March 1', 'May 31', NULL, NULL, NULL, '32975f54-4568-40ec-b2ae-a5dbc4088927'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
EXEC sp_add_regulation 'ON', 8, 'Method: Bow and arrow, spear, and dip net during daylight hours only', 'March 1', 'May 31', NULL, NULL, NULL, '32975f54-4568-40ec-b2ae-a5dbc4088927'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
EXEC sp_add_regulation 'ON', 9, 'Method: Bow and arrow, spear, and dip net during daylight hours only', 'March 1', 'May 31', NULL, NULL, NULL, '32975f54-4568-40ec-b2ae-a5dbc4088927'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
EXEC sp_add_regulation 'ON', 10, 'Method: Bow and arrow, spear, and dip net during daylight hours only', 'March 1', 'May 31', NULL, NULL, NULL, '32975f54-4568-40ec-b2ae-a5dbc4088927'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
EXEC sp_add_regulation 'ON', 11, 'Method: Bow and arrow, spear, and dip net during daylight hours only', 'March 1', 'May 31', NULL, NULL, NULL, '32975f54-4568-40ec-b2ae-a5dbc4088927'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
EXEC sp_add_regulation 'ON', 12, 'Method: Bow and arrow, spear, and dip net during daylight hours only', 'March 1', 'May 31', NULL, NULL, NULL, '32975f54-4568-40ec-b2ae-a5dbc4088927'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
EXEC sp_add_regulation 'ON', 13, 'Method: Bow and arrow, spear, and dip net during daylight hours only', 'March 1', 'May 31', NULL, NULL, NULL, '32975f54-4568-40ec-b2ae-a5dbc4088927'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
EXEC sp_add_regulation 'ON', 14, 'Method: Bow and arrow, spear, and dip net during daylight hours only', 'March 1', 'May 31', NULL, NULL, NULL, '32975f54-4568-40ec-b2ae-a5dbc4088927'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
EXEC sp_add_regulation 'ON', 15, 'Method: Bow and arrow, spear, and dip net during daylight hours only. Except Algonquin Park', 'March 1', 'May 31', NULL, NULL, NULL, '32975f54-4568-40ec-b2ae-a5dbc4088927'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
EXEC sp_add_regulation 'ON', 16, 'Method: Bow and arrow, spear, and dip net during daylight hours only', 'March 1', 'May 31', NULL, NULL, NULL, '32975f54-4568-40ec-b2ae-a5dbc4088927'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
EXEC sp_add_regulation 'ON', 17, 'Method: Bow and arrow, spear, and dip net during daylight hours only', 'second Saturday in May', 'May 31', NULL, NULL, NULL, '32975f54-4568-40ec-b2ae-a5dbc4088927'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
EXEC sp_add_regulation 'ON', 18, 'Method: Bow and arrow, spear, and dip net during daylight hours only', 'March 1', 'May 31', NULL, NULL, NULL, '32975f54-4568-40ec-b2ae-a5dbc4088927'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
EXEC sp_add_regulation 'ON', 19, 'Method: Bow and arrow, spear, and dip net during daylight hours only', 'March 1', 'May 31', NULL, NULL, NULL, '32975f54-4568-40ec-b2ae-a5dbc4088927'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
EXEC sp_add_regulation 'ON', 20, 'Method: Bow and arrow, spear, and dip net during daylight hours only', 'March 1', 'May 31', NULL, NULL, NULL, '32975f54-4568-40ec-b2ae-a5dbc4088927'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
GO
------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Zone 1
------------------------------------------------------------------------------------------------------------------------------------------------------------
EXEC sp_add_regulation 'ON', 1, '', 'January 1', 'December 31', NULL, NULL, NULL, 'a35109a0-63ba-4bf5-8a25-2e7e39b74f6e'
    , NULL, 'https://www.ontario.ca/page/sport-fishing-variation-order-fisheries-management-zone-1', 2019, 0
EXEC sp_add_regulation 'ON', 1, '', 'January 1', 'December 31', NULL, NULL, NULL, '5ab8a0ee-a5ca-43e6-b628-73e2bc12266e'
    , NULL, 'https://www.ontario.ca/page/sport-fishing-variation-order-fisheries-management-zone-1', 2019, 0
EXEC sp_add_regulation 'ON', 1, '', 'January 1', 'December 31', NULL, NULL, NULL, '073cd69e-d9f4-4377-a746-b6f32cb9e3ba'
    , NULL, 'https://www.ontario.ca/page/sport-fishing-variation-order-fisheries-management-zone-1', 2019, 0
EXEC sp_add_regulation 'ON', 1, '', 'January 1', 'December 31', '5, not more than 1 greater than 40 cm', '2, not more than 1 greater than 40', NULL, 'f124f917-d11f-4ed9-9b59-863d184cbfed'
    , NULL, 'https://www.ontario.ca/page/sport-fishing-variation-order-fisheries-management-zone-1', 2019, 0
EXEC sp_add_regulation 'ON', 1, '', 'January 1', 'December 31', NULL, NULL, NULL, '6dbf1306-dc10-421a-a29b-b260d540a0ae'
    , NULL, 'https://www.ontario.ca/page/sport-fishing-variation-order-fisheries-management-zone-1', 2019, 0
EXEC sp_add_regulation 'ON', 1, '', 'January 1', 'December 31', NULL, NULL, NULL, '969c00e3-1ed1-4845-bffc-a1dc51e2105d'
    , NULL, 'https://www.ontario.ca/page/sport-fishing-variation-order-fisheries-management-zone-1', 2019, 0
EXEC sp_add_regulation 'ON', 1, '', 'May 1', 'June 30', 0, 0, NULL, 'c0fe652f-cfa2-4148-94c1-24fc2d7140eb'
    , NULL, 'https://www.ontario.ca/page/sport-fishing-variation-order-fisheries-management-zone-1', 2019, 0
EXEC sp_add_regulation 'ON', 1, '', NULL, NULL, '1, any size', '3, any size', NULL, 'f3c65c73-f913-43b8-9f22-965ab095d13e'
    , NULL, 'https://www.ontario.ca/page/sport-fishing-variation-order-fisheries-management-zone-1', 2019, 0
EXEC sp_add_regulation 'ON', 1, '', NULL, NULL, '12, any size', '6, any size', NULL, 'e8003bda-f3ce-415d-834e-ff9b157b2da1'
    , NULL, 'https://www.ontario.ca/page/sport-fishing-variation-order-fisheries-management-zone-1', 2019, 0
EXEC sp_add_regulation 'ON', 1, '', 'January 1', 'December 31', NULL, NULL, NULL, '2038693f-d38c-43c8-b0ce-4e96b0f9af7e'
    , NULL, 'https://www.ontario.ca/page/sport-fishing-variation-order-fisheries-management-zone-1', 2019, 0
EXEC sp_add_regulation 'ON', 1, '', 'January 1', 'December 31', NULL, NULL, NULL, 'a85ebf22-4ab9-4a91-a14a-cef6c8e64d97'
    , NULL, 'https://www.ontario.ca/page/sport-fishing-variation-order-fisheries-management-zone-1', 2019, 0
EXEC sp_add_regulation 'ON', 1, '', 'January 1', 'December 31', NULL, NULL, NULL, '896837e4-3fe3-44c6-baee-5a490fbf64c8'        -- Muskellunge
    , NULL, 'https://www.ontario.ca/page/sport-fishing-variation-order-fisheries-management-zone-1', 2019, 0
EXEC sp_add_regulation 'ON', 1, '', NULL, NULL, '6, not more than 2 greater than 61 cm, of which not more than 1 is greater than 86 cm'
    , '2, not more than 1 greater than 61 cm, none greater than 86 cm', NULL, 'd07efe63-baf4-4dd1-9b1c-fe94c5860185'
    , NULL, 'https://www.ontario.ca/page/sport-fishing-variation-order-fisheries-management-zone-1', 2019, 0
EXEC sp_add_regulation 'ON', 1, '', 'January 1', 'December 31', NULL, NULL, NULL, 'b3a33573-8bc6-4803-b977-10f673aad711'
    , NULL, 'https://www.ontario.ca/page/sport-fishing-variation-order-fisheries-management-zone-1', 2019, 0
EXEC sp_add_regulation 'ON', 1, '', 'January 1', 'December 31', NULL, NULL, NULL, '19c45110-154d-477f-ba55-309be16e54ca'
    , NULL, 'https://www.ontario.ca/page/sport-fishing-variation-order-fisheries-management-zone-1', 2019, 0
EXEC sp_add_regulation 'ON', 1, '', 'January 1', 'December 31', NULL, NULL, NULL, 'dfb7eb63-9d05-4e7a-b58c-fe510014baee'
    , NULL, 'https://www.ontario.ca/page/sport-fishing-variation-order-fisheries-management-zone-1', 2019, 0
EXEC sp_add_regulation 'ON', 1, '', NULL, NULL, '4, not more than 1 greater than 46 cm', '2, not more than 1 greater than 46 cm', NULL, '2cffb500-3e59-4120-9460-055856e9ac5c'
    , NULL, 'https://www.ontario.ca/page/sport-fishing-variation-order-fisheries-management-zone-1', 2019, 0
EXEC sp_add_regulation 'ON', 1, '', NULL, NULL, '4, not more than 1 greater than 46 cm', '2, not more than 1 greater than 46 cm', NULL, '8014674d-ca30-4e61-8fa2-4d80d94e5f45'
    , NULL, 'https://www.ontario.ca/page/sport-fishing-variation-order-fisheries-management-zone-1', 2019, 0
EXEC sp_add_regulation 'ON', 1, '', NULL, NULL, '50, any size', '25, any size', NULL, '2460a02d-cd68-435f-be2a-0f5aa1275dd4'
    , NULL, 'https://www.ontario.ca/page/sport-fishing-variation-order-fisheries-management-zone-1', 2019, 0
GO
------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Zone 2
------------------------------------------------------------------------------------------------------------------------------------------------------------
EXEC sp_add_regulation 'ON', 2, '', 'January 1', 'December 31', NULL, NULL, NULL, 'a35109a0-63ba-4bf5-8a25-2e7e39b74f6e'        --- Atlantic Salmon
    , NULL, 'https://www.ontario.ca/page/sport-fishing-variation-order-fisheries-management-zone-2', 2019, 0
EXEC sp_add_regulation 'ON', 2, '', 'January 1', 'December 31', NULL, NULL, NULL, '5ab8a0ee-a5ca-43e6-b628-73e2bc12266e'        -- Black & White Crappie
    , NULL, 'https://www.ontario.ca/page/sport-fishing-variation-order-fisheries-management-zone-2', 2019, 0
EXEC sp_add_regulation 'ON', 2, '', 'January 1', 'December 31', NULL, NULL, NULL, '073cd69e-d9f4-4377-a746-b6f32cb9e3ba'        -- Black & White Crappie
    , NULL, 'https://www.ontario.ca/page/sport-fishing-variation-order-fisheries-management-zone-2', 2019, 0
EXEC sp_add_regulation 'ON', 2, '', 'Day after Labour Day', 'December 31', '5, not more than 1 greater than 30 cm', '2, not more than 1 greater than 40'       -- Brook Trout
    , NULL, 'f124f917-d11f-4ed9-9b59-863d184cbfed', NULL, 'https://www.ontario.ca/page/sport-fishing-variation-order-fisheries-management-zone-2', 2019, 0
EXEC sp_add_regulation 'ON', 2, '', NULL, NULL, '5, any size', '2, any size', NULL, '6dbf1306-dc10-421a-a29b-b260d540a0ae'       -- Brown Trout
    , NULL, 'https://www.ontario.ca/page/sport-fishing-variation-order-fisheries-management-zone-2', 2019, 0
EXEC sp_add_regulation 'ON', 2, '', 'January 1', 'December 31', NULL, NULL, NULL, '969c00e3-1ed1-4845-bffc-a1dc51e2105d'         -- Channel Catfish
    , NULL, 'https://www.ontario.ca/page/sport-fishing-variation-order-fisheries-management-zone-2', 2019, 0
EXEC sp_add_regulation 'ON', 2, '', 'May 1', 'June 30', 0, 0, NULL, 'c0fe652f-cfa2-4148-94c1-24fc2d7140eb'                       --  Lake Sturgeon
    , NULL, 'https://www.ontario.ca/page/sport-fishing-variation-order-fisheries-management-zone-2', 2019, 0
EXEC sp_add_regulation 'ON', 2, '', 'October 1', 'December 31', '2, not more than 1 greater than 56 cm from September 1 to September 30 any size from January 1 to August 31'
    , '1, any size', NULL, 'f3c65c73-f913-43b8-9f22-965ab095d13e'                                                                -- Lake Trout
    , NULL, 'https://www.ontario.ca/page/sport-fishing-variation-order-fisheries-management-zone-2', 2019, 0
EXEC sp_add_regulation 'ON', 2, '', NULL, NULL, '12, any size', '6, any size', NULL, 'e8003bda-f3ce-415d-834e-ff9b157b2da1'      -- Lake Whitefish
    , NULL, 'https://www.ontario.ca/page/sport-fishing-variation-order-fisheries-management-zone-2', 2019, 0
EXEC sp_add_regulation 'ON', 2, '', NULL, NULL, '2, must be less than 35 cm from January 1 to June 30 and December 1 to December 31 4, no size limit from July 1 to November 30'
    , '1, must be less than 35 cm from January 1 to June 30 and December 1 to December 31 2, no size limit from July 1 to November 30'
    , NULL, '2038693f-d38c-43c8-b0ce-4e96b0f9af7e'                                                                              -- Largemouth  Bass
    , NULL, 'https://www.ontario.ca/page/sport-fishing-variation-order-fisheries-management-zone-2', 2019, 0
EXEC sp_add_regulation 'ON', 2, '', NULL, NULL, '2, must be less than 35 cm from January 1 to June 30 and December 1 to December 31 4, no size limit from July 1 to November 30'
    , '1, must be less than 35 cm from January 1 to June 30 and December 1 to December 31 2, no size limit from July 1 to November 30'
    , NULL, 'a85ebf22-4ab9-4a91-a14a-cef6c8e64d97'                                                                              -- Smallmouth Bass
    , NULL, 'https://www.ontario.ca/page/sport-fishing-variation-order-fisheries-management-zone-2', 2019, 0

EXEC sp_add_regulation 'ON', 2, '', 'January 1', 'The Friday before the 3rd Saturday in June', '1, must be greater than 91 cm', 0, NULL, '896837e4-3fe3-44c6-baee-5a490fbf64c8'        -- Muskellunge
    , NULL, 'https://www.ontario.ca/page/sport-fishing-variation-order-fisheries-management-zone-2', 2019, 0
EXEC sp_add_regulation 'ON', 2, '', NULL, NULL, '6, not more than 2 greater than 61 cm, of which not more than 1 is greater than 86 cm'
    , '2, not more than 1 greater than 61 cm, none greater than 86 cm', NULL, 'd07efe63-baf4-4dd1-9b1c-fe94c5860185'
    , NULL, 'https://www.ontario.ca/page/sport-fishing-variation-order-fisheries-management-zone-2', 2019, 0
EXEC sp_add_regulation 'ON', 2, '', 'January 1', 'December 31', NULL, NULL, NULL, 'b3a33573-8bc6-4803-b977-10f673aad711'
    , NULL, 'https://www.ontario.ca/page/sport-fishing-variation-order-fisheries-management-zone-2', 2019, 0
EXEC sp_add_regulation 'ON', 2, '', 'January 1', 'December 31', NULL, NULL, NULL, '19c45110-154d-477f-ba55-309be16e54ca'
    , NULL, 'https://www.ontario.ca/page/sport-fishing-variation-order-fisheries-management-zone-2', 2019, 0
EXEC sp_add_regulation 'ON', 2, '', 'January 1', 'December 31', NULL, NULL, NULL, 'dfb7eb63-9d05-4e7a-b58c-fe510014baee'
    , NULL, 'https://www.ontario.ca/page/sport-fishing-variation-order-fisheries-management-zone-2', 2019, 0
EXEC sp_add_regulation 'ON', 2, '', NULL, NULL, '4, not more than 1 greater than 46 cm', '2, not more than 1 greater than 46 cm', NULL, '2cffb500-3e59-4120-9460-055856e9ac5c'
    , NULL, 'https://www.ontario.ca/page/sport-fishing-variation-order-fisheries-management-zone-2', 2019, 0
EXEC sp_add_regulation 'ON', 2, '', NULL, NULL, '4, not more than 1 greater than 46 cm', '2, not more than 1 greater than 46 cm', NULL, '8014674d-ca30-4e61-8fa2-4d80d94e5f45'
    , NULL, 'https://www.ontario.ca/page/sport-fishing-variation-order-fisheries-management-zone-2', 2019, 0
EXEC sp_add_regulation 'ON', 2, '', NULL, NULL, '50, any size', '25, any size', NULL, '2460a02d-cd68-435f-be2a-0f5aa1275dd4'
    , NULL, 'https://www.ontario.ca/page/sport-fishing-variation-order-fisheries-management-zone-2', 2019, 0
GO
------------------------------------------------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------------------------------------------

