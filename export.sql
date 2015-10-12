BEGIN TRANSACTION;

  DROP DOMAIN IF EXISTS EntityUUID CASCADE;
  CREATE DOMAIN EntityUUID AS CHAR(16);

  DROP DOMAIN IF EXISTS EntityUUIDS CASCADE;
  CREATE DOMAIN EntityUUIDs CHAR(16)[];

  DROP TYPE IF EXISTS Gender CASCADE;
  CREATE TYPE Gender AS ENUM ('Female', 'Male');

  DROP TYPE IF EXISTS FileType CASCADE;
  CREATE TYPE FileTYpe AS ENUM ('Image', 'Video', 'Playlist', 'Document', 'Audio', 'Octet');

  DROP TYPE IF EXISTS SecurityGroup CASCADE;
  CREATE TYPE SecurityGroup AS ENUM ('Me', 'Contacts', 'Everyone');

  SET search_path TO public;

  -------------------- USERS --------------------

  DROP TABLE IF EXISTS Users CASCADE;

  CREATE TABLE Users (
    id EntityUUID PRIMARY KEY,
    name text,
    siteURL TEXT NOT NULL DEFAULT '',
    about TEXT NOT NULL DEFAULT '',
    coverId EntityUUID NOT NULL DEFAULT '0000000000000000',
    avatarId EntityUUID NOT NULL DEFAULT '0000000000000000',
    birthday TIMESTAMP WITH TIME ZONE,
    gender Gender,
    firstName TEXT NOT NULL DEFAULT '',
    lastName TEXT NOT NULL DEFAULT '',
    address TEXT,
    locationMeta JSONB,
    languages text[],
    creationTime TIMESTAMP WITH TIME ZONE,
    loginDate TIMESTAMP WITH TIME ZONE,
    tutorialFinished BOOLEAN NOT NULL DEFAULT 'no',
    onboardingFinished BOOLEAN NOT NULL DEFAULT 'no',
    verified BOOLEAN NOT NULL DEFAULT 'no'
  );

  INSERT INTO Users (
  SELECT
    value  ->> 'id'                            AS id,
    value  ->> 'name'                          AS name,
    value  ->> 'siteURL'                       AS siteURL,
    value  ->> 'about'                         AS about,
    value  ->> 'coverId'                       AS coverId,
    value  ->> 'avatarId'                      AS avatarId,
    (value ->> 'birthday')::timestamptz        AS birthday,
    cast((value ->> 'gender') AS Gender)       AS gender,
    value  ->> 'firstName'                     AS firstName,
    value  ->> 'lastName'                      AS lastName,
    value  ->> 'address'                       AS address,
    value  -> 'locationMeta'                   AS locationMeta,
    (WITH langs AS
      (SELECT
        jsonb_array_elements_text(value -> 'languages')
        AS elements)
      SELECT array_agg(elements) FROM langs)   AS languages,
    (value ->> 'creationTime')::timestamptz    AS creationTime,
    (value ->> 'loginDate')::timestamptz       AS loginDate,
    (value ->> 'tutorialFinished')::boolean    AS tutorialFinished,
    (value ->> 'onboardingFinished')::boolean  AS onboardingFinished,
    (value ->> 'verified')::boolean            AS verified
  FROM buckets.Users);

  -------------------- StashFiles --------------------

  DROP TABLE IF EXISTS StashFiles;

  CREATE TABLE StashFiles (
    id EntityUUID PRIMARY KEY,
    name TEXT,
    size INT,
    -- "tags": [],
    s3Key TEXT,
    ownerId EntityUUID, -- REFERENCES Users(id),
    fileType FileType,
    mimeType VARCHAR(128),
    -- "parentId": "0630b317fc81715a-root",
    s3Bucket varchar(128),
    accessTime TIMESTAMP WITH TIME ZONE,
    origFileId EntityUUID, -- constraint?
    updateTime TIMESTAMP WITH TIME ZONE,
    description TEXT,
    creationTime TIMESTAMP WITH TIME ZONE,
    origAuthorId EntityUUID
  );

  DELETE FROM buckets.stashfiles WHERE key='087c4e72c7486000';

  INSERT INTO StashFiles (
    SELECT
      value ->> 'id'                        AS id,
      value ->> 'name'                      AS name,
      (value ->> 'size')::INTEGER           AS size,
      value ->> 's3Key'                     AS s3Key,
      value ->> 'ownerId'                   AS ownerId,
      (value ->> 'fileType')::FileType      AS FileType,
      value ->> 'mimeType'                  AS mimeType,
      value ->> 's3Bucket'                  AS s3Bucket,
      (value ->> 'accessTime')::TIMESTAMPTZ AS accessTIme,
      value ->> 'origFileId'                AS origFileId,
      (value ->> 'updateTime')::TIMESTAMPTZ AS updateTime,
      value ->> 'description'               AS description,
      (value ->> 'creationTime')::TIMESTAMPTZ AS creationTime,
      value ->> 'origAuthorId'              AS origAuthorId
    FROM buckets.StashFiles);

  INSERT INTO Users (id) VALUES ('0000000000000000');

  UPDATE Users SET avatarId='0200000000000001' WHERE avatarId NOT IN (SELECT id FROM StashFiles);
  UPDATE Users SET coverId='0200000000010000' WHERE coverId NOT IN (SELECT id FROM StashFiles);

  DELETE FROM StashFIles WHERE ownerId NOT IN (SELECT id FROM Users);
  DELETE FROM StashFIles WHERE origAuthorId NOT IN (SELECT id FROM Users);

  ALTER TABLE StashFiles ADD CONSTRAINT stashfiles_ownerid_references_users
    FOREIGN KEY (ownerId) REFERENCES Users(id);

  ALTER TABLE StashFiles ADD CONSTRAINT stashfiles_origauthorid_references_users
    FOREIGN KEY (origauthorid) REFERENCES Users(id);

  ALTER TABLE Users ADD CONSTRAINT users_avatarid_references_stashfiles
    FOREIGN KEY (avatarId) REFERENCES StashFiles(id);

  ALTER TABLE Users ADD CONSTRAINT users_coverId_references_stashfiles
    FOREIGN KEY (coverId) REFERENCES StashFiles(id);

  -- create table stashfilemetadata
  -- create table attachments

  -------------------- STORIES --------------------

  DROP TABLE IF EXISTS Stories;
  CREATE TABLE Stories (
    id EntityUUID PRIMARY KEY,
    ownerId EntityUUID REFERENCES Users(id) ON DELETE CASCADE,
    title TEXT,
    description TEXT,
    coverId EntityUUID, -- REFERENCES StashFiles(id)
    coverX INT,
    coverY INT,
    public BOOLEAN,
    lang VARCHAR(10),
    inviteCollaboratorACL SecurityGroup,
    updateTime TIMESTAMP WITH TIME ZONE,
    creationTime TIMESTAMP WITH TIME ZONE,
    categories EntityUUIDS
  );

  DELETE FROM buckets.Stories WHERE value ->> 'ownerId' NOT IN (SELECT id FROM Users);

  INSERT INTO Stories (SELECT
    value  ->> 'id'                            AS id,
    value  ->> 'ownerId'                       AS ownerId,
    value  ->> 'title'                         AS title,
    value  ->> 'description'                   AS description,
    value  ->> 'coverId'                       AS coverId,
    (value ->> 'coverX')::INT                  AS coverX,
    (value ->> 'coverY')::INT                  AS coverY,
    (value ->> 'public')::BOOL                 AS public,
    value  ->> 'lang'                          AS lang,
    cast((value ->> 'inviteCollaboratorACL') AS SecurityGroup) AS inviteCollaboratorACL,
    (value ->> 'updateTime')::TIMESTAMPTZ      AS updateTime,
    (value ->> 'creationTime')::TIMESTAMPTZ    AS creationTime,
    (WITH categs AS
      (SELECT
        jsonb_array_elements_text(value -> 'categories')
        AS elements)
      SELECT array_agg(elements) FROM categs) AS categories
  FROM buckets.Stories);

  CREATE INDEX idx_stories_creationTime ON stories(creationTime);

  -------------------- MOMENTS --------------------

  DROP TABLE IF EXISTS Moments;
  CREATE TABLE Moments (
    id EntityUUID PRIMARY KEY,
    storyID EntityUUID, -- REFERENCES Stories(id) ON DELETE CASCADE,
    ownerId EntityUUID, -- REFERENCES Users(id) ON DELETE CASCADE,
    title TEXT,
    lang VARCHAR(10),
    content JSONB NOT NULL,
    deleted BOOLEAN NOT NULL DEFAULT 'NO',
    creationTime TIMESTAMP WITH TIME ZONE,
    updateTime TIMESTAMP WITH TIME ZONE
  );

  INSERT INTO Moments (
    SELECT
      value  ->> 'id'                         AS id,
      value  ->> 'storyId'                    AS storyId,
      value  ->> 'ownerId'                    AS ownerId,
      value  ->> 'title'                      AS title,
      value  ->> 'lang'                       AS lang,
      value  ->  'content'                    AS content,
      (value ->> 'deleted')::BOOLEAN          AS deleted,
      (value ->> 'creationTime')::TIMESTAMPTZ AS creationTime,
      (value ->> 'updateTime')::TIMESTAMPTZ   AS updateTime
  FROM buckets.Moments);

  CREATE INDEX idx_moments_storyId ON moments(storyId);
  CREATE INDEX idx_moments_ownerId ON moments(ownerId);

  DELETE FROM Moments WHERE ownerId NOT IN (SELECT id FROM Users);
  DELETE FROM Moments WHERE storyId NOT IN (SELECT id FROM Stories);
  ALTER TABLE Moments ADD CONSTRAINT moments_ownerId_references_users FOREIGN KEY (ownerId) REFERENCES Users(id);
  ALTER TABLE Moments ADD CONSTRAINT moments_storyId_references_stories FOREIGN KEY (storyId) REFERENCES Stories(id);

  CREATE INDEX idx_moments_creationTime ON moments(creationTime);

  -- TODO: attachments from moments to table attachments

  -- select moments.id, users.name, moments.title, stories.title, moments.creationTime from moments join stories on (moments.storyId=stories.id) join users on (moments.ownerId=users.id) order by moments.creationtime limit 50;

  --  select moments.id, moments.title, momentOwners.name, stories.title, storyOwners.name from moments join stories on (stories.id = moments.storyId) join users as storyOwners on (storyOwners.id = stories.ownerId) join users as momentOwners on (momentOwners.id = moments.ownerId) where storyOwners.id <> momentOwners.id order by moments.creationTime limit 50;

  -------------------- FOLLOWING --------------------

  DROP TABLE IF EXISTS rel_follows;

  SELECT split_part(key, '-', 1) AS "from", split_part(key, '-', 2) AS "to", value AS "date"
    INTO Follows FROM buckets.follows;

  DELETE FROM Follows WHERE "from" NOT IN (SELECT id FROM users);
  DELETE FROM Follows WHERE "to" NOT IN (SELECT id FROM users);
  ALTER TABLE Follows ADD CONSTRAINT follows_from_ref_user FOREIGN KEY ("from") REFERENCES users(id);
  ALTER TABLE Follows ADD CONSTRAINT follows_to_ref_user FOREIGN KEY ("to") REFERENCES users(id);
  CREATE INDEX idx_follows_from ON Follows("from");
  CREATE INDEX idx_follows_to ON Follows("to");

  -------------------- SUBSCRIPTIONS --------------------

  DROP TABLE IF EXISTS rel_subscribed;

  SELECT split_part(key, '-', 1) AS "from", split_part(key, '-', 2) AS "to", value AS "date"
    INTO Subscribed FROM buckets.subscribed;

  DELETE FROM Subscribed WHERE "from" NOT IN (SELECT id FROM users);
  DELETE FROM Subscribed WHERE "to" NOT IN (SELECT id FROM stories);
  ALTER TABLE Subscribed ADD CONSTRAINT subscribed_from_ref_user FOREIGN KEY ("from") REFERENCES users(id);
  ALTER TABLE Subscribed ADD CONSTRAINT subscribed_to_ref_story FOREIGN KEY ("to") REFERENCES stories(id);
  CREATE INDEX idx_subscribed_user ON Subscribed("from");
  CREATE INDEX idx_subscribed_story ON Subscribed("to");

  --  :: top followers
  --  select name, follows from (select "from" as userId, count("to") as follows from rel_follows group by "from" order by follows desc limit 50) as topFollowers join users on (topFollowers.userId=users.id);

  --  :: top followed
  -- select name, followers from (select "to" as userId, count("from") as followers from rel_follows group by "to" order by followers desc limit 50) as topFollowed join users on (topFollowed.userId=users.id);

  -- :: users with most public moments
  -- select userId, name, nmoments from (select moments.ownerId as userId, count(moments.id) as nmoments from moments join stories on (stories.id=moments.storyId) where stories.public=true group by moments.ownerId order by nmoments desc limit 50) as topPublic join users on (users.id=topPublic.userId);

  --  :: stories with moments from most authors
  --
  --  select storyId, stories.title, count(moments.id) as "total moments", count(distinct moments.ownerId) as authors from moments join stories on (moments.storyId=stories.id) group by storyId, stories.title order by authors desc limit 20;

END TRANSACTION;
