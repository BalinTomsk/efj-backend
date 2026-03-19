CREATE TABLE StationFailure(
    mli varchar(64) NOT NULL,
    stamp datetime2 NOT NULL DEFAULT GETDATE()
);
