CREATE TABLE news (
    news_id BINARY(16) NOT NULL DEFAULT (UUID_TO_BIN(UUID())),

    news_title VARCHAR(128) NOT NULL,
    news_author VARCHAR(128) NOT NULL,
    news_author_link VARCHAR(1024) NULL,
    news_source VARCHAR(255) NULL,
    news_source_link VARCHAR(1024) NULL,

    news_publish BOOLEAN NOT NULL DEFAULT FALSE,

    news_photo0 MEDIUMBLOB  NULL,
    news_photo_author0 VARCHAR(64) NULL,
    news_video_link VARCHAR(255) NULL,

    news_paragraph1 LONGTEXT NULL,
    news_photo1 MEDIUMBLOB  NULL,
    news_photo_author1 VARCHAR(64) NULL,

    news_paragraph2 LONGTEXT NULL,
    news_photo2 MEDIUMBLOB  NULL,
    news_photo_author2 VARCHAR(64) NULL,

    news_stamp DATETIME(6) NOT NULL DEFAULT (UTC_TIMESTAMP(6)),
    news_paragraph0 LONGTEXT NULL,

    id BIGINT NOT NULL AUTO_INCREMENT,

    stamp DATETIME(6) NOT NULL DEFAULT (UTC_TIMESTAMP(6)),

    lake_id BINARY(16) NULL,
    country CHAR(2) NULL,

    fish1_id BINARY(16) NULL,
    fish2_id BINARY(16) NULL,
    fish3_id BINARY(16) NULL,

    news_photo_alt0 VARCHAR(128) NULL,
    news_photo_alt1 VARCHAR(128) NULL,
    news_photo_alt2 VARCHAR(128) NULL,

    PRIMARY KEY (news_id),
    UNIQUE KEY uq_news_id_auto (id)
) ENGINE=InnoDB;