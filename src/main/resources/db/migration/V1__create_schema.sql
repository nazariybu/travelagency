-- V1: initial schema of the TravelAgency database

CREATE TABLE `Role` (
  `id`        bigint       NOT NULL AUTO_INCREMENT,
  `isActual`  bit(1)       NOT NULL DEFAULT b'1',
  `role_name` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_role_name` (`role_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `Country` (
  `countryId` bigint       NOT NULL AUTO_INCREMENT,
  `isActual`  bit(1)       NOT NULL DEFAULT b'1',
  `name`      varchar(255) NOT NULL,
  PRIMARY KEY (`countryId`),
  UNIQUE KEY `uk_country_name` (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `City` (
  `cityId`     bigint       NOT NULL AUTO_INCREMENT,
  `isActual`   bit(1)       NOT NULL DEFAULT b'1',
  `name`       varchar(255) NOT NULL,
  `country_id` bigint       DEFAULT NULL,
  PRIMARY KEY (`cityId`),
  KEY `idx_city_country` (`country_id`),
  CONSTRAINT `fk_city_country` FOREIGN KEY (`country_id`) REFERENCES `Country` (`countryId`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `Hotel` (
  `hotelId`     bigint       NOT NULL AUTO_INCREMENT,
  `description` varchar(255) DEFAULT NULL,
  `isActual`    bit(1)       NOT NULL DEFAULT b'1',
  `location`    varchar(255) NOT NULL,
  `name`        varchar(255) NOT NULL,
  `city_id`     bigint       DEFAULT NULL,
  PRIMARY KEY (`hotelId`),
  UNIQUE KEY `uk_hotel_name` (`name`),
  KEY `idx_hotel_city` (`city_id`),
  CONSTRAINT `fk_hotel_city` FOREIGN KEY (`city_id`) REFERENCES `City` (`cityId`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `RoomClassification` (
  `id`       bigint       NOT NULL AUTO_INCREMENT,
  `isActual` bit(1)       NOT NULL DEFAULT b'1',
  `name`     varchar(255) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_room_classification_name` (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `User` (
  `userId`                  bigint       NOT NULL AUTO_INCREMENT,
  `email`                   varchar(255) NOT NULL,
  `account_non_expired`     bit(1)       NOT NULL,
  `account_non_locked`      bit(1)       NOT NULL,
  `isActual`                bit(1)       NOT NULL DEFAULT b'1',
  `credentials_non_expired` bit(1)       NOT NULL,
  `enabled`                 bit(1)       NOT NULL,
  `login`                   varchar(255) NOT NULL,
  `name`                    varchar(255) NOT NULL,
  `password`                varchar(255) NOT NULL,
  `surname`                 varchar(255) NOT NULL,
  `role_id`                 bigint       DEFAULT NULL,
  PRIMARY KEY (`userId`),
  UNIQUE KEY `uk_user_email` (`email`),
  UNIQUE KEY `uk_user_login` (`login`),
  KEY `idx_user_role` (`role_id`),
  CONSTRAINT `fk_user_role` FOREIGN KEY (`role_id`) REFERENCES `Role` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `Booking` (
  `bookingId`   bigint NOT NULL AUTO_INCREMENT,
  `end_date`    date   DEFAULT NULL,
  `isActual`    bit(1) NOT NULL DEFAULT b'1',
  `numOfPeople` int    NOT NULL,
  `start_date`  date   DEFAULT NULL,
  `totalPrice`  double NOT NULL,
  `hotel_id`    bigint DEFAULT NULL,
  `user_id`     bigint DEFAULT NULL,
  PRIMARY KEY (`bookingId`),
  KEY `idx_booking_hotel` (`hotel_id`),
  KEY `idx_booking_user` (`user_id`),
  CONSTRAINT `fk_booking_hotel` FOREIGN KEY (`hotel_id`) REFERENCES `Hotel` (`hotelId`),
  CONSTRAINT `fk_booking_user`  FOREIGN KEY (`user_id`)  REFERENCES `User` (`userId`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `Room` (
  `roomId`                 bigint NOT NULL AUTO_INCREMENT,
  `capacity`               int    NOT NULL,
  `isActual`               bit(1) NOT NULL DEFAULT b'1',
  `isAvailable`            bit(1) NOT NULL DEFAULT b'1',
  `number`                 int    NOT NULL,
  `price`                  double NOT NULL,
  `booking_id`             bigint DEFAULT NULL,
  `hotel_id`               bigint DEFAULT NULL,
  `room_classification_id` bigint DEFAULT NULL,
  PRIMARY KEY (`roomId`),
  KEY `idx_room_booking` (`booking_id`),
  KEY `idx_room_hotel` (`hotel_id`),
  KEY `idx_room_classification` (`room_classification_id`),
  CONSTRAINT `fk_room_booking`        FOREIGN KEY (`booking_id`)             REFERENCES `Booking` (`bookingId`),
  CONSTRAINT `fk_room_hotel`          FOREIGN KEY (`hotel_id`)               REFERENCES `Hotel` (`hotelId`),
  CONSTRAINT `fk_room_classification` FOREIGN KEY (`room_classification_id`) REFERENCES `RoomClassification` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;