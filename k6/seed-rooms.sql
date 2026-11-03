-- Test rooms for the k6 load test.
-- The seed (V2__seed_data.sql) creates hotels but no rooms, so hotel search returns nothing to book.
-- Adds 10 rooms of each class (Standard/Deluxe/Suite) to every hotel = 240 rooms.
-- Safe to run again: it skips a hotel that already has room number 101.
-- Run on vm-db:  mysql -u root -p travelagency < seed-rooms.sql

INSERT INTO Room (capacity, isActual, isAvailable, number, price, hotel_id, room_classification_id)
SELECT c.capacity, b'1', b'1', c.base + n.n, c.price, h.hotelId, c.id
FROM Hotel h
CROSS JOIN (SELECT 1 n UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5
            UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9 UNION ALL SELECT 10) n
CROSS JOIN (SELECT rc.id, CASE rc.name WHEN 'Standard' THEN 100 WHEN 'Deluxe' THEN 200 ELSE 300 END AS base,
                   CASE rc.name WHEN 'Standard' THEN 2 WHEN 'Deluxe' THEN 3 ELSE 4 END AS capacity,
                   CASE rc.name WHEN 'Standard' THEN 80 WHEN 'Deluxe' THEN 140 ELSE 250 END AS price
            FROM RoomClassification rc WHERE rc.name IN ('Standard', 'Deluxe', 'Suite')) c
WHERE NOT EXISTS (SELECT 1 FROM Room r WHERE r.hotel_id = h.hotelId AND r.number = 101);