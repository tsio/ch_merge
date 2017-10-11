--
-- PostgreSQL database dump
--

-- Dumped from database version 9.5.1
-- Dumped by pg_dump version 9.5.3

SET statement_timeout = 0;
SET lock_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: plpgsql; Type: EXTENSION; Schema: -; Owner: 
--

CREATE EXTENSION IF NOT EXISTS plpgsql WITH SCHEMA pg_catalog;


--
-- Name: EXTENSION plpgsql; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION plpgsql IS 'PL/pgSQL procedural language';


SET search_path = public, pg_catalog;

--
-- Name: enstore2chimera(); Type: FUNCTION; Schema: public; Owner: chimera
--

CREATE FUNCTION enstore2chimera() RETURNS void
    LANGUAGE plpgsql
    AS $$
          DECLARE
            ichain  RECORD;
            istring text[];
            igroup text;
            istore text;
            l_entries text[];
            ilocation text;
          BEGIN
            FOR ichain IN SELECT * FROM t_level_4 LOOP
              ilocation = f_enstore2uri(encode(ichain.ifiledata,'escape'));
              IF ilocation IS NULL THEN
                raise warning 'ilocation is NULL %',ichain.inumber;
                CONTINUE;
              ELSE
                BEGIN
                  INSERT INTO t_locationinfo VALUES ( ichain.inumber, 0, ilocation, 10, NOW(), NOW(), 1);
                  EXCEPTION WHEN unique_violation THEN
                        -- do nothing
                    RAISE NOTICE 'Tape location for % aready exist.', ichain.inumber;
                    CONTINUE;
                    END;
                l_entries = string_to_array(encode(ichain.ifiledata,'escape'), E'\n');
                BEGIN
                  INSERT INTO t_storageinfo
                  VALUES (ichain.inumber,'enstore','enstore',l_entries[4]);
                  EXCEPTION WHEN unique_violation THEN
                        -- do nothing
                    RAISE NOTICE 'Storage info for % aready exist.', ichain.inumber;
                  CONTINUE;
                    END;
              END IF;
            END LOOP;
          END;
          $$;


ALTER FUNCTION public.enstore2chimera() OWNER TO chimera;

--
-- Name: f_create_inode(bigint, character varying, character varying, integer, integer, integer, integer, integer, bigint, integer, timestamp without time zone); Type: FUNCTION; Schema: public; Owner: chimera
--

CREATE FUNCTION f_create_inode(parent bigint, name character varying, id character varying, type integer, mode integer, nlink integer, uid integer, gid integer, size bigint, io integer, now timestamp without time zone) RETURNS bigint
    LANGUAGE plpgsql
    AS $$
            DECLARE
                newid bigint;
            BEGIN
                INSERT INTO t_inodes VALUES (id,type,mode,nlink,uid,gid,size,io,now,now,now,now,0) RETURNING inumber INTO newid;
                INSERT INTO t_dirs VALUES (parent, newid, name);
                UPDATE t_inodes SET inlink=inlink+1,imtime=now,ictime=now,igeneration=igeneration+1 WHERE inumber = parent;
                RETURN newid;
            END;
            $$;


ALTER FUNCTION public.f_create_inode(parent bigint, name character varying, id character varying, type integer, mode integer, nlink integer, uid integer, gid integer, size bigint, io integer, now timestamp without time zone) OWNER TO chimera;

--
-- Name: f_create_inode(character varying, character varying, character varying, integer, integer, integer, integer, integer, bigint, integer, timestamp without time zone); Type: FUNCTION; Schema: public; Owner: chimera
--

CREATE FUNCTION f_create_inode(parent character varying, name character varying, id character varying, type integer, mode integer, nlink integer, uid integer, gid integer, size bigint, io integer, now timestamp without time zone) RETURNS void
    LANGUAGE plpgsql
    AS $$
            BEGIN
                INSERT INTO t_inodes VALUES (id,type,mode,nlink,uid,gid,size,io,now,now,now,now,0);
                INSERT INTO t_dirs VALUES (parent, name, id);
                UPDATE t_inodes SET inlink=inlink+1,imtime=now,ictime=now,igeneration=igeneration+1 WHERE ipnfsid=parent;
            END;
            $$;


ALTER FUNCTION public.f_create_inode(parent character varying, name character varying, id character varying, type integer, mode integer, nlink integer, uid integer, gid integer, size bigint, io integer, now timestamp without time zone) OWNER TO chimera;

--
-- Name: f_enstore2uri(character varying); Type: FUNCTION; Schema: public; Owner: chimera
--

CREATE FUNCTION f_enstore2uri(character varying) RETURNS character varying
    LANGUAGE plpgsql
    AS $_$
	  DECLARE
	    l_level4 varchar := $1;
            l_entries text[];
	  BEGIN
	    -- convert level4 data into array of strings
	    l_entries = string_to_array(l_level4, E'\n');
	    -- string_to_array skips empty lines. as a result we get 9 lines instead of 11
	    return 'enstore://enstore/?volume=' || l_entries[1]  || '&location_cookie=' || l_entries[2]  ||
            '&size='                        || l_entries[3]  || '&file_family='     || l_entries[4]  ||
            '&map_file='                    || l_entries[6]  || '&pnfsid_file='     || l_entries[7]  ||
            '&pnfsid_map='                  || l_entries[8]  || '&bfid='            || l_entries[9]  ||
            '&origdrive='                   || l_entries[10] || '&crc='             || l_entries[11] ||
            '&original_name='               || uri_encode(l_entries[5]);
	  END;
	  $_$;


ALTER FUNCTION public.f_enstore2uri(character varying) OWNER TO chimera;

--
-- Name: f_enstorelevel2locationinfo(); Type: FUNCTION; Schema: public; Owner: chimera
--

CREATE FUNCTION f_enstorelevel2locationinfo() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
          DECLARE
            l_entries text[];
                location text;
            file_data varchar;
          BEGIN
            IF (TG_OP = 'INSERT') THEN
                  location := f_enstore2uri(encode(NEW.ifiledata,'escape'));
              IF location IS NULL THEN
                -- encp only creates empty layer 4 file
                -- so NEW.ifiledata is null
                INSERT INTO t_locationinfo VALUES (NEW.inumber,0,'enstore:',10,NOW(),NOW(),1);
                INSERT INTO t_storageinfo
               VALUES (NEW.inumber,'enstore','enstore','enstore');
              ELSE
                    l_entries = string_to_array(encode(NEW.ifiledata,'escape'), E'\n');
                INSERT INTO t_locationinfo VALUES (NEW.inumber,0,location,10,NOW(),NOW(),1);
                INSERT INTO t_storageinfo
               VALUES (NEW.inumber,'enstore','enstore',l_entries[4]);
                  END IF;
                   --
                   -- we assume all files coming through level4 to be CUSTODIAL-NEARLINE
                   --
                   -- the block below is needed for files written directly by encp
                   --
              BEGIN
                    UPDATE t_inodes SET iaccess_latency = 0, iretention_policy = 0 WHERE inumber = NEW.inumber;
              END;
            ELSEIF (TG_OP = 'UPDATE')  THEN
              file_data := encode(NEW.ifiledata, 'escape');
                  IF ( file_data = E'\n') THEN
                UPDATE t_locationinfo SET ilocation = file_data
                      WHERE inumber = NEW.inumber and itype=0;
                  ELSE
                location := f_enstore2uri(file_data);
                    IF location IS NOT NULL THEN
                  UPDATE t_locationinfo
                SET ilocation = f_enstore2uri(file_data)
                        WHERE inumber = NEW.inumber and itype=0;
                      l_entries = string_to_array(file_data, E'\n');
                  UPDATE t_storageinfo SET istoragesubgroup=l_entries[4]
                    WHERE  inumber = NEW.inumber;
                    END IF;
                  END IF;
                END IF;
                RETURN NEW;
              END;
          $$;


ALTER FUNCTION public.f_enstorelevel2locationinfo() OWNER TO chimera;

--
-- Name: f_locationinfo2trash(); Type: FUNCTION; Schema: public; Owner: chimera
--

CREATE FUNCTION f_locationinfo2trash() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
            BEGIN
                IF (TG_OP = 'DELETE') THEN
                    INSERT INTO t_locationinfo_trash
                        SELECT
                            OLD.ipnfsid,
                            itype,
                            ilocation,
                            ipriority,
                            ictime,
                            iatime,
                            istate
                        FROM t_locationinfo
                        WHERE inumber = OLD.inumber
                      UNION
                        SELECT OLD.ipnfsid, 2, '', 0, now(), now(), 1;
                END IF;

                RETURN OLD;
            END;

            $$;


ALTER FUNCTION public.f_locationinfo2trash() OWNER TO chimera;

--
-- Name: inode2path(character varying); Type: FUNCTION; Schema: public; Owner: chimera
--

CREATE FUNCTION inode2path(character varying) RETURNS character varying
    LANGUAGE sql
    AS $_$
                 SELECT inumber2path(pnfsid2inumber($1));
            $_$;


ALTER FUNCTION public.inode2path(character varying) OWNER TO chimera;

--
-- Name: inumber2path(bigint); Type: FUNCTION; Schema: public; Owner: chimera
--

CREATE FUNCTION inumber2path(bigint) RETURNS character varying
    LANGUAGE plpgsql
    AS $_$
            DECLARE
                 inumber bigint := $1;
                 path    varchar := '';
                 entry   record;
            BEGIN
                LOOP
                    SELECT * INTO entry FROM t_dirs WHERE ichild = inumber;
                    IF FOUND AND entry.iparent != inumber
                    THEN
                        path := '/' || entry.iname || path;
                        inumber := entry.iparent;
                    ELSE
                        EXIT;
                    END IF;
                END LOOP;

                RETURN path;
            END;
            $_$;


ALTER FUNCTION public.inumber2path(bigint) OWNER TO chimera;

--
-- Name: inumber2pnfsid(bigint); Type: FUNCTION; Schema: public; Owner: chimera
--

CREATE FUNCTION inumber2pnfsid(bigint) RETURNS character varying
    LANGUAGE sql
    AS $_$
                SELECT ipnfsid FROM t_inodes WHERE inumber = $1;
            $_$;


ALTER FUNCTION public.inumber2pnfsid(bigint) OWNER TO chimera;

--
-- Name: path2inode(character varying, character varying); Type: FUNCTION; Schema: public; Owner: chimera
--

CREATE FUNCTION path2inode(root character varying, path character varying) RETURNS character varying
    LANGUAGE sql
    AS $_$
                 SELECT inumber2pnfsid(path2inumber(pnfsid2inumber($1), $2));
            $_$;


ALTER FUNCTION public.path2inode(root character varying, path character varying) OWNER TO chimera;

SET default_tablespace = '';

SET default_with_oids = false;

--
-- Name: t_inodes; Type: TABLE; Schema: public; Owner: chimera
--

CREATE TABLE t_inodes (
    ipnfsid character varying(36) NOT NULL,
    itype integer NOT NULL,
    imode integer NOT NULL,
    inlink integer NOT NULL,
    iuid integer NOT NULL,
    igid integer NOT NULL,
    isize bigint NOT NULL,
    iio integer NOT NULL,
    ictime timestamp without time zone NOT NULL,
    iatime timestamp without time zone NOT NULL,
    imtime timestamp without time zone NOT NULL,
    icrtime timestamp without time zone DEFAULT now() NOT NULL,
    igeneration bigint DEFAULT 0 NOT NULL,
    iaccess_latency smallint,
    iretention_policy smallint,
    inumber bigint NOT NULL
)
WITH (fillfactor='75');


ALTER TABLE t_inodes OWNER TO chimera;

--
-- Name: COLUMN t_inodes.icrtime; Type: COMMENT; Schema: public; Owner: chimera
--

COMMENT ON COLUMN t_inodes.icrtime IS 'file/directory creation timestamp';


--
-- Name: COLUMN t_inodes.igeneration; Type: COMMENT; Schema: public; Owner: chimera
--

COMMENT ON COLUMN t_inodes.igeneration IS 'file/directory change indicator';


--
-- Name: COLUMN t_inodes.iaccess_latency; Type: COMMENT; Schema: public; Owner: chimera
--

COMMENT ON COLUMN t_inodes.iaccess_latency IS 'file''s access latency';


--
-- Name: COLUMN t_inodes.iretention_policy; Type: COMMENT; Schema: public; Owner: chimera
--

COMMENT ON COLUMN t_inodes.iretention_policy IS 'file''s retention policy';


--
-- Name: path2inodes(bigint, character varying); Type: FUNCTION; Schema: public; Owner: chimera
--

CREATE FUNCTION path2inodes(root bigint, path character varying, OUT inode t_inodes) RETURNS SETOF t_inodes
    LANGUAGE plpgsql
    AS $$
            DECLARE
                dir      bigint;
                elements text[] := string_to_array(path, '/');
                inodes   t_inodes[];
                parent   t_inodes;
                link     varchar;
            BEGIN
                -- Find the inode of the root
                SELECT * INTO inode FROM t_inodes WHERE inumber = root;
                IF NOT FOUND THEN
                    RETURN;
                END IF;

                -- We build an array of the inodes for the path
                inodes := ARRAY[inode];

                -- For each path element
                FOR i IN 1..array_upper(elements,1) LOOP
                    -- Return empty set if not a directory
                    IF inode.itype != 16384 THEN
                        RETURN;
                    END IF;

                    -- The ID of the directory
                    dir := inode.inumber;

                    -- Lookup the next path element
                    CASE
                    WHEN elements[i] = '.' THEN
                        CONTINUE;
                    WHEN elements[i] = '..' THEN
                        SELECT p.* INTO parent
                            FROM t_inodes p JOIN t_dirs d ON p.inumber = d.iparent
                            WHERE d.ichild = dir;
                        IF FOUND THEN
                            inode := parent;
                        ELSE
                            CONTINUE;
                        END IF;
                    ELSE
                        SELECT c.* INTO inode
                            FROM t_inodes c JOIN t_dirs d ON c.inumber = d.ichild
                            WHERE d.iparent = dir AND d.iname = elements[i];

                        -- Return the empty set if not found
                        IF NOT FOUND THEN
                            RETURN;
                        END IF;
                    END CASE;

                    -- Append the inode to the result set
                    inodes := array_append(inodes, inode);

                    -- If inode is a symbolic link
                    IF inode.itype = 40960 THEN
                        -- Read the link
                        SELECT encode(ifiledata,'escape') INTO STRICT link
                            FROM t_inodes_data WHERE inumber = inode.inumber;

                        -- If absolute path then resolve from the file system root
                        IF link LIKE '/%' THEN
                            dir := pnfsid2inumber('000000000000000000000000000000000000');
                            link := substring(link from 2);

                            -- Call recursively and add inodes to result set
                            FOR inode IN SELECT * FROM path2inodes(dir, link) LOOP
                                inodes := array_append(inodes, inode);
                            END LOOP;
                        ELSE
                            -- Call recursively and add inodes to result set; skip
                            -- first inode as it is the inode of dir
                            FOR inode IN SELECT * FROM path2inodes(dir, link) OFFSET 1 LOOP
                                inodes := array_append(inodes, inode);
                            END LOOP;
                        END IF;

                        -- Return empty set if link could not be resolved
                        IF NOT FOUND THEN
                            RETURN;
                        END IF;

                        -- Continue from the inode pointed to by the link
                        inode = inodes[array_upper(inodes,1)];
                    END IF;
                END LOOP;

                -- Output all inodes
                FOR i IN 1..array_upper(inodes,1) LOOP
                    inode := inodes[i];
                    RETURN NEXT;
                END LOOP;
            END;
            $$;


ALTER FUNCTION public.path2inodes(root bigint, path character varying, OUT inode t_inodes) OWNER TO chimera;

--
-- Name: path2inumber(bigint, character varying); Type: FUNCTION; Schema: public; Owner: chimera
--

CREATE FUNCTION path2inumber(root bigint, path character varying) RETURNS bigint
    LANGUAGE plpgsql
    AS $$
            DECLARE
                id       bigint := root;
                elements varchar[] := string_to_array(path, '/');
                child    bigint;
                type     int;
                link     varchar;
            BEGIN
                FOR i IN 1..array_upper(elements,1) LOOP
                    CASE
                    WHEN elements[i] = '.' THEN
                        child := id;
                    WHEN elements[i] = '..' THEN
                        SELECT iparent INTO child FROM t_dirs WHERE ichild = id;
                        IF NOT FOUND THEN
                            child := id;
                        END IF;
                    ELSE
                        SELECT d.ichild, c.itype INTO child, type FROM t_dirs d JOIN t_inodes c ON d.ichild = c.inumber WHERE d.iparent = id AND d.iname = elements[i];
                        IF type = 40960 THEN
                            SELECT encode(ifiledata,'escape') INTO link FROM t_inodes_data WHERE inumber = child;
                            IF link LIKE '/%' THEN
                                child := path2inumber(pnfsid2inumber('000000000000000000000000000000000000'), substring(link from 2));
                            ELSE
                                child := path2inumber(id, link);
                            END IF;
                        END IF;
                    END CASE;
                    IF child IS NULL THEN
                        RETURN NULL;
                    END IF;
                    id := child;
                END LOOP;
                RETURN id;
            END;
            $$;


ALTER FUNCTION public.path2inumber(root bigint, path character varying) OWNER TO chimera;

--
-- Name: pnfsid2inumber(character varying); Type: FUNCTION; Schema: public; Owner: chimera
--

CREATE FUNCTION pnfsid2inumber(character varying) RETURNS bigint
    LANGUAGE sql
    AS $_$
                SELECT inumber FROM t_inodes WHERE ipnfsid = $1;
            $_$;


ALTER FUNCTION public.pnfsid2inumber(character varying) OWNER TO chimera;

--
-- Name: uri_decode(text); Type: FUNCTION; Schema: public; Owner: chimera
--

CREATE FUNCTION uri_decode(input_txt text) RETURNS text
    LANGUAGE plpgsql IMMUTABLE STRICT
    AS $$
	 DECLARE
	 output_txt bytea = '';
	 byte text;
	 BEGIN
	 IF input_txt IS NULL THEN
	 return NULL;
	 END IF;
	 FOR byte IN (select (regexp_matches(input_txt, '(%..|.)', 'g'))[1]) LOOP
	 IF length(byte) = 3 THEN
	 output_txt = output_txt || decode(substring(byte, 2, 2), 'hex');
	 ELSE
	 output_txt = output_txt || byte::bytea;
	 END IF;
	 END LOOP;
	 RETURN convert_from(output_txt, 'utf8');
	 END
	 $$;


ALTER FUNCTION public.uri_decode(input_txt text) OWNER TO chimera;

--
-- Name: uri_encode(text); Type: FUNCTION; Schema: public; Owner: chimera
--

CREATE FUNCTION uri_encode(input_txt text) RETURNS text
    LANGUAGE plpgsql IMMUTABLE STRICT
    AS $$
	 DECLARE
	 output_txt text = '';
	 ch text;
	 BEGIN
	 IF input_txt IS NULL THEN
	 return NULL;
	 END IF;
	 FOR ch IN (select (regexp_matches(input_txt, '(.)', 'g'))[1]) LOOP
	 --
	 -- chr(39) is a single quote
	 --
	 IF  ch ~ '[-a-zA-Z0-9.*_!~()/]' OR ch = chr(39) THEN
         output_txt = output_txt || ch;
	 ELSE
         output_txt = output_txt || '%' || encode(ch::bytea,'hex');
	 END IF;
	 END LOOP;
	 RETURN output_txt;
	 END
	 $$;


ALTER FUNCTION public.uri_encode(input_txt text) OWNER TO chimera;

--
-- Name: databasechangelog; Type: TABLE; Schema: public; Owner: chimera
--

CREATE TABLE databasechangelog (
    id character varying(255) NOT NULL,
    author character varying(255) NOT NULL,
    filename character varying(255) NOT NULL,
    dateexecuted timestamp without time zone NOT NULL,
    orderexecuted integer NOT NULL,
    exectype character varying(10) NOT NULL,
    md5sum character varying(35),
    description character varying(255),
    comments character varying(255),
    tag character varying(255),
    liquibase character varying(20),
    contexts character varying(255),
    labels character varying(255),
    deployment_id character varying(10)
);


ALTER TABLE databasechangelog OWNER TO chimera;

--
-- Name: databasechangeloglock; Type: TABLE; Schema: public; Owner: chimera
--

CREATE TABLE databasechangeloglock (
    id integer NOT NULL,
    locked boolean NOT NULL,
    lockgranted timestamp without time zone,
    lockedby character varying(255)
);


ALTER TABLE databasechangeloglock OWNER TO chimera;

--
-- Name: t_acl; Type: TABLE; Schema: public; Owner: chimera
--

CREATE TABLE t_acl (
    inumber bigint NOT NULL,
    ace_order integer DEFAULT 0 NOT NULL,
    rs_type integer NOT NULL,
    type integer DEFAULT 0 NOT NULL,
    access_msk integer DEFAULT 0 NOT NULL,
    who integer NOT NULL,
    who_id integer,
    flags integer
);


ALTER TABLE t_acl OWNER TO chimera;

--
-- Name: t_dirs; Type: TABLE; Schema: public; Owner: chimera
--

CREATE TABLE t_dirs (
    iparent bigint NOT NULL,
    ichild bigint NOT NULL,
    iname character varying(255) NOT NULL
);


ALTER TABLE t_dirs OWNER TO chimera;

--
-- Name: t_groups; Type: TABLE; Schema: public; Owner: chimera
--

CREATE TABLE t_groups (
    id integer NOT NULL,
    group_name character varying(64) NOT NULL
);


ALTER TABLE t_groups OWNER TO chimera;

--
-- Name: t_inodes_checksum; Type: TABLE; Schema: public; Owner: chimera
--

CREATE TABLE t_inodes_checksum (
    inumber bigint NOT NULL,
    itype integer NOT NULL,
    isum character varying(128) NOT NULL
);


ALTER TABLE t_inodes_checksum OWNER TO chimera;

--
-- Name: t_inodes_data; Type: TABLE; Schema: public; Owner: chimera
--

CREATE TABLE t_inodes_data (
    inumber bigint NOT NULL,
    ifiledata bytea
);


ALTER TABLE t_inodes_data OWNER TO chimera;

--
-- Name: t_inodes_inumber_seq; Type: SEQUENCE; Schema: public; Owner: chimera
--

CREATE SEQUENCE t_inodes_inumber_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE t_inodes_inumber_seq OWNER TO chimera;

--
-- Name: t_inodes_inumber_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: chimera
--

ALTER SEQUENCE t_inodes_inumber_seq OWNED BY t_inodes.inumber;


--
-- Name: t_level_1; Type: TABLE; Schema: public; Owner: chimera
--

CREATE TABLE t_level_1 (
    inumber bigint NOT NULL,
    imode integer NOT NULL,
    inlink integer NOT NULL,
    iuid integer NOT NULL,
    igid integer NOT NULL,
    isize integer NOT NULL,
    ictime timestamp without time zone NOT NULL,
    iatime timestamp without time zone NOT NULL,
    imtime timestamp without time zone NOT NULL,
    ifiledata bytea
);


ALTER TABLE t_level_1 OWNER TO chimera;

--
-- Name: t_level_2; Type: TABLE; Schema: public; Owner: chimera
--

CREATE TABLE t_level_2 (
    inumber bigint NOT NULL,
    imode integer NOT NULL,
    inlink integer NOT NULL,
    iuid integer NOT NULL,
    igid integer NOT NULL,
    isize integer NOT NULL,
    ictime timestamp without time zone NOT NULL,
    iatime timestamp without time zone NOT NULL,
    imtime timestamp without time zone NOT NULL,
    ifiledata bytea
);


ALTER TABLE t_level_2 OWNER TO chimera;

--
-- Name: t_level_3; Type: TABLE; Schema: public; Owner: chimera
--

CREATE TABLE t_level_3 (
    inumber bigint NOT NULL,
    imode integer NOT NULL,
    inlink integer NOT NULL,
    iuid integer NOT NULL,
    igid integer NOT NULL,
    isize integer NOT NULL,
    ictime timestamp without time zone NOT NULL,
    iatime timestamp without time zone NOT NULL,
    imtime timestamp without time zone NOT NULL,
    ifiledata bytea
);


ALTER TABLE t_level_3 OWNER TO chimera;

--
-- Name: t_level_4; Type: TABLE; Schema: public; Owner: chimera
--

CREATE TABLE t_level_4 (
    inumber bigint NOT NULL,
    imode integer NOT NULL,
    inlink integer NOT NULL,
    iuid integer NOT NULL,
    igid integer NOT NULL,
    isize integer NOT NULL,
    ictime timestamp without time zone NOT NULL,
    iatime timestamp without time zone NOT NULL,
    imtime timestamp without time zone NOT NULL,
    ifiledata bytea
);


ALTER TABLE t_level_4 OWNER TO chimera;

--
-- Name: t_level_5; Type: TABLE; Schema: public; Owner: chimera
--

CREATE TABLE t_level_5 (
    inumber bigint NOT NULL,
    imode integer NOT NULL,
    inlink integer NOT NULL,
    iuid integer NOT NULL,
    igid integer NOT NULL,
    isize integer NOT NULL,
    ictime timestamp without time zone NOT NULL,
    iatime timestamp without time zone NOT NULL,
    imtime timestamp without time zone NOT NULL,
    ifiledata bytea
);


ALTER TABLE t_level_5 OWNER TO chimera;

--
-- Name: t_level_6; Type: TABLE; Schema: public; Owner: chimera
--

CREATE TABLE t_level_6 (
    inumber bigint NOT NULL,
    imode integer NOT NULL,
    inlink integer NOT NULL,
    iuid integer NOT NULL,
    igid integer NOT NULL,
    isize integer NOT NULL,
    ictime timestamp without time zone NOT NULL,
    iatime timestamp without time zone NOT NULL,
    imtime timestamp without time zone NOT NULL,
    ifiledata bytea
);


ALTER TABLE t_level_6 OWNER TO chimera;

--
-- Name: t_level_7; Type: TABLE; Schema: public; Owner: chimera
--

CREATE TABLE t_level_7 (
    inumber bigint NOT NULL,
    imode integer NOT NULL,
    inlink integer NOT NULL,
    iuid integer NOT NULL,
    igid integer NOT NULL,
    isize integer NOT NULL,
    ictime timestamp without time zone NOT NULL,
    iatime timestamp without time zone NOT NULL,
    imtime timestamp without time zone NOT NULL,
    ifiledata bytea
);


ALTER TABLE t_level_7 OWNER TO chimera;

--
-- Name: t_locationinfo; Type: TABLE; Schema: public; Owner: chimera
--

CREATE TABLE t_locationinfo (
    inumber bigint NOT NULL,
    itype integer NOT NULL,
    ipriority integer NOT NULL,
    ictime timestamp without time zone NOT NULL,
    iatime timestamp without time zone NOT NULL,
    istate integer NOT NULL,
    ilocation character varying(1024) NOT NULL
);


ALTER TABLE t_locationinfo OWNER TO chimera;

--
-- Name: t_locationinfo_trash; Type: TABLE; Schema: public; Owner: chimera
--

CREATE TABLE t_locationinfo_trash (
    ipnfsid character varying(36) NOT NULL,
    itype integer NOT NULL,
    ilocation character varying(1024) NOT NULL,
    ipriority integer NOT NULL,
    ictime timestamp without time zone NOT NULL,
    iatime timestamp without time zone NOT NULL,
    istate integer NOT NULL
);


ALTER TABLE t_locationinfo_trash OWNER TO chimera;

--
-- Name: t_storageinfo; Type: TABLE; Schema: public; Owner: chimera
--

CREATE TABLE t_storageinfo (
    inumber bigint NOT NULL,
    ihsmname character varying(64) NOT NULL,
    istoragegroup character varying(64) NOT NULL,
    istoragesubgroup character varying(256) NOT NULL
);


ALTER TABLE t_storageinfo OWNER TO chimera;

--
-- Name: t_tags; Type: TABLE; Schema: public; Owner: chimera
--

CREATE TABLE t_tags (
    inumber bigint NOT NULL,
    itagid bigint NOT NULL,
    isorign integer NOT NULL,
    itagname character varying(255) NOT NULL
);


ALTER TABLE t_tags OWNER TO chimera;

--
-- Name: t_tags_inodes; Type: TABLE; Schema: public; Owner: chimera
--

CREATE TABLE t_tags_inodes (
    itagid bigint NOT NULL,
    imode integer NOT NULL,
    inlink integer NOT NULL,
    iuid integer NOT NULL,
    igid integer NOT NULL,
    isize integer NOT NULL,
    ictime timestamp without time zone NOT NULL,
    iatime timestamp without time zone NOT NULL,
    imtime timestamp without time zone NOT NULL,
    ivalue bytea
);


ALTER TABLE t_tags_inodes OWNER TO chimera;

--
-- Name: t_tags_inodes2_itagid_seq; Type: SEQUENCE; Schema: public; Owner: chimera
--

CREATE SEQUENCE t_tags_inodes2_itagid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE t_tags_inodes2_itagid_seq OWNER TO chimera;

--
-- Name: t_tags_inodes2_itagid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: chimera
--

ALTER SEQUENCE t_tags_inodes2_itagid_seq OWNED BY t_tags_inodes.itagid;


--
-- Name: inumber; Type: DEFAULT; Schema: public; Owner: chimera
--

ALTER TABLE ONLY t_inodes ALTER COLUMN inumber SET DEFAULT nextval('t_inodes_inumber_seq'::regclass);


--
-- Name: itagid; Type: DEFAULT; Schema: public; Owner: chimera
--

ALTER TABLE ONLY t_tags_inodes ALTER COLUMN itagid SET DEFAULT nextval('t_tags_inodes2_itagid_seq'::regclass);


--
-- Data for Name: databasechangelog; Type: TABLE DATA; Schema: public; Owner: chimera
--

COPY databasechangelog (id, author, filename, dateexecuted, orderexecuted, exectype, md5sum, description, comments, tag, liquibase, contexts, labels, deployment_id) FROM stdin;
1	tigran	org/dcache/chimera/changelog/changeset-1.8.0.xml	2016-06-27 15:15:12.503399	1	EXECUTED	7:0dfb0413e67dda74b16e1991670974e2	createTable tableName=t_dirs; createTable tableName=t_groups; createTable tableName=t_inodes; createTable tableName=t_inodes_checksum; createTable tableName=t_inodes_data; createTable tableName=t_level_1; createTable tableName=t_level_2; createTab...		\N	3.5.1	\N	\N	7033338983
1.1	tigran	org/dcache/chimera/changelog/changeset-1.8.0.xml	2016-06-27 15:15:12.627423	2	EXECUTED	7:46d244d19a742044ed69e1747eb28f55	createIndex indexName=i_dirs_ipnfsid, tableName=t_dirs		\N	3.5.1	\N	\N	7033338983
2	tigran	org/dcache/chimera/changelog/changeset-1.8.0.xml	2016-06-27 15:15:12.639708	3	EXECUTED	7:6990d2ef332cd12effa4b8e870047a5e	insert tableName=t_inodes; insert tableName=t_dirs; insert tableName=t_dirs		\N	3.5.1	\N	\N	7033338983
3	tigran	org/dcache/chimera/changelog/changeset-1.8.0.xml	2016-06-27 15:15:12.682284	4	EXECUTED	7:9a3cd4245e7d9c0b7015a20f9c284f2d	createProcedure; createProcedure; createProcedure; createProcedure		\N	3.5.1	\N	\N	7033338983
4	tigran	org/dcache/chimera/changelog/changeset-1.9.2.xml	2016-06-27 15:15:12.734128	5	EXECUTED	7:009b5be6d6f424a8d4ffc26023180832	createTable tableName=t_acl; addPrimaryKey constraintName=t_acl_pkey, tableName=t_acl; addForeignKeyConstraint baseTableName=t_acl, constraintName=t_acl_fkey, referencedTableName=t_inodes; createIndex indexName=i_t_acl_rs_id, tableName=t_acl		\N	3.5.1	\N	\N	7033338983
5	tigran	org/dcache/chimera/changelog/changeset-1.9.3.xml	2016-06-27 15:15:12.78527	6	EXECUTED	7:22588d4ccaa29b0e1f8958feda20d713	createTable tableName=t_access_latency; createTable tableName=t_retention_policy; addForeignKeyConstraint baseTableName=t_access_latency, constraintName=t_access_latency_ipnfsid_fkey, referencedTableName=t_inodes; addForeignKeyConstraint baseTable...		\N	3.5.1	\N	\N	7033338983
6	tigran	org/dcache/chimera/changelog/changeset-1.9.3.xml	2016-06-27 15:15:12.79696	7	MARK_RAN	7:16d2e4e79f53afadad377b82b1338da1	createTable tableName=t_access_latency; createTable tableName=t_retention_policy; addForeignKeyConstraint baseTableName=t_access_latency, constraintName=t_access_latency_ipnfsid_fkey, referencedTableName=t_inodes; addForeignKeyConstraint baseTable...		\N	3.5.1	\N	\N	7033338983
7.3	tigran	org/dcache/chimera/changelog/changeset-1.9.12.xml	2016-06-27 15:15:12.807498	8	EXECUTED	7:44f6fc5af2832715524dc0811934b1e8	createProcedure		\N	3.5.1	\N	\N	7033338983
8	tigran	org/dcache/chimera/changelog/changeset-1.9.12.xml	2016-06-27 15:15:13.105079	9	EXECUTED	7:11e2237ac7a2571351a0142d8e592c49	modifyDataType columnName=ipnfsid, tableName=t_inodes; modifyDataType columnName=ipnfsid, tableName=t_dirs; modifyDataType columnName=iparent, tableName=t_dirs; modifyDataType columnName=ipnfsid, tableName=t_inodes_data; modifyDataType columnName=...		\N	3.5.1	\N	\N	7033338983
9	tigran	org/dcache/chimera/changelog/changeset-1.9.13.xml	2016-06-27 15:15:13.121526	10	EXECUTED	7:cad6a1d47963b73b743d8324812fc90e	createProcedure		\N	3.5.1	\N	\N	7033338983
10	litvinse	org/dcache/chimera/changelog/changeset-2.3.xml	2016-06-27 15:15:13.142858	11	EXECUTED	7:3d41f66591e7f446f73dc9674bc28ad2	createProcedure; createProcedure; createProcedure		\N	3.5.1	\N	\N	7033338983
11	litvinse	org/dcache/chimera/changelog/changeset-2.3.xml	2016-06-27 15:15:13.154449	12	EXECUTED	7:a066c975825e87cba5a8ff0a0d545742	modifyDataType columnName=istoragesubgroup, tableName=t_storageinfo		\N	3.5.1	\N	\N	7033338983
12	tigran	org/dcache/chimera/changelog/changeset-2.3.xml	2016-06-27 15:15:13.19304	13	EXECUTED	7:d267f5e8cade9dece6586970b456bed8	dropForeignKeyConstraint baseTableName=t_level_1, constraintName=t_level_1_ipnfsid_fkey; dropForeignKeyConstraint baseTableName=t_level_2, constraintName=t_level_2_ipnfsid_fkey; dropForeignKeyConstraint baseTableName=t_level_3, constraintName=t_le...		\N	3.5.1	\N	\N	7033338983
15.2	behrmann	org/dcache/chimera/changelog/changeset-2.8.xml	2016-06-27 15:15:13.206692	14	EXECUTED	7:f86c109273986bc6bf4d251682e20bd7	sql	Prepare t_inodes for whole table update	\N	3.5.1	\N	\N	7033338983
15.3	tigran	org/dcache/chimera/changelog/changeset-2.8.xml	2016-06-27 15:15:13.325106	15	EXECUTED	7:7c8447bfc38b82b3332ed31c72e735ae	addColumn tableName=t_inodes; sql	Add creation time column	\N	3.5.1	\N	\N	7033338983
15.4	tigran	org/dcache/chimera/changelog/changeset-2.8.xml	2016-06-27 15:15:13.332992	16	EXECUTED	7:3721c0dd3c79f626d985ae8747b64f7f	sql	Restore t_inodes fillfactor to reasonable value	\N	3.5.1	\N	\N	7033338983
17.1	litvinse	org/dcache/chimera/changelog/changeset-2.8.xml	2016-06-27 15:15:13.341883	17	EXECUTED	7:a8ede4230eb74a2e938839a057b4759b	createProcedure; createProcedure; createProcedure		\N	3.5.1	\N	\N	7033338983
18.1	litvinse	org/dcache/chimera/changelog/changeset-2.9.xml	2016-06-27 15:15:13.355524	18	EXECUTED	7:aaf8f4715d07789e3d4dd67ab2e386fc	createProcedure; createProcedure	use encode on bytea field	\N	3.5.1	\N	\N	7033338983
19.1	tigran	org/dcache/chimera/changelog/changeset-2.9.xml	2016-06-27 15:15:13.37917	19	EXECUTED	7:4224472fd6ff7dded41e436de866355b	addColumn tableName=t_inodes		\N	3.5.1	\N	\N	7033338983
1	behrmann	org/dcache/chimera/changelog/changeset-2.10.xml	2016-06-27 15:15:13.385956	20	EXECUTED	7:3a65d05523bb357ed29d49ecb7d098f9	createIndex indexName=i_tags_itagid, tableName=t_tags	Create index on itagid needed by referential integrity constraint.	\N	3.5.1	\N	\N	7033338983
2	behrmann	org/dcache/chimera/changelog/changeset-2.10.xml	2016-06-27 15:15:13.389453	21	EXECUTED	7:34f6e1e7f5a45ef9ae509b21006ffe7e	sql	Adjust statistics target for t_tags(itagid) to avoid bad query planning for tag inode deletion	\N	3.5.1	\N	\N	7033338983
1	behrmann	org/dcache/chimera/changelog/changeset-2.13.xml	2016-06-27 15:15:13.394487	22	EXECUTED	7:eb2d5f1df13d6bf3d4b52079c2dfa28d	createProcedure	Update trash trigger to add an itype 2 marker to trash.	\N	3.5.1	\N	\N	7033338983
3	behrmann	org/dcache/chimera/changelog/changeset-2.13.xml	2016-06-27 15:15:13.398845	23	EXECUTED	7:f6c8aceed07de36b10d13bb437fd8b74	createIndex indexName=i_locationinfo_trash_itype_ilocation, tableName=t_locationinfo_trash		\N	3.5.1	\N	\N	7033338983
4	behrmann	org/dcache/chimera/changelog/changeset-2.13.xml	2016-06-27 15:15:13.419571	24	EXECUTED	7:bb7bdfc499d3d8b6dcd4c7eeaae27740	createTable tableName=t_tags_inodes2; sql; dropForeignKeyConstraint baseTableName=t_tags, constraintName=t_tags_itagid_fkey; sql; sql; addForeignKeyConstraint baseTableName=t_tags, constraintName=t_tags_itagid_fkey, referencedTableName=t_tags_inod...	Removes leaked tag inodes	\N	3.5.1	\N	\N	7033338983
2	behrmann	org/dcache/chimera/changelog/changeset-2.14.xml	2016-06-27 15:15:13.424143	25	EXECUTED	7:c26ad33e589eb3cb7c66cc1f02031475	sql	Drop tag population trigger	\N	3.5.1	\N	\N	7033338983
3.1	behrmann	org/dcache/chimera/changelog/changeset-2.14.xml	2016-06-27 15:15:13.433275	26	EXECUTED	7:a674bbf828e6f099cac519dd19c24bd0	sql		\N	3.5.1	\N	\N	7033338983
23.1	tigran	org/dcache/chimera/changelog/changeset-2.14.xml	2016-06-27 15:15:13.461159	27	EXECUTED	7:0f67820d9acd11c92788482623f6f695	sql; sql	Prepare t_inodes for whole table update	\N	3.5.1	\N	\N	7033338983
23.2	tigran	org/dcache/chimera/changelog/changeset-2.14.xml	2016-06-27 15:15:13.480118	28	EXECUTED	7:48477e9913f8dfbbf430eff0e3fedaab	addColumn tableName=t_inodes; sql; dropTable tableName=t_access_latency; dropTable tableName=t_retention_policy	Add access latency/retention policy columns	\N	3.5.1	\N	\N	7033338983
23.3	tigran	org/dcache/chimera/changelog/changeset-2.14.xml	2016-06-27 15:15:13.486104	29	EXECUTED	7:3721c0dd3c79f626d985ae8747b64f7f	sql	Prepare t_inodes for whole table update	\N	3.5.1	\N	\N	7033338983
21	tigran	org/dcache/chimera/changelog/changeset-2.14.xml	2016-06-27 15:15:13.491008	30	EXECUTED	7:42e485d362cc55eb1ad844bfa793347a	dropColumn columnName=address_msk, tableName=t_acl	Remove address mask from ACL	\N	3.5.1	\N	\N	7033338983
24.1	litvinse	org/dcache/chimera/changelog/changeset-2.14.xml	2016-06-27 15:15:13.506206	31	EXECUTED	7:a9642d3a7da231497eb2535a0de81a74	createProcedure	Fix trigger on insert or update on t_level_4	\N	3.5.1	\N	\N	7033338983
4	behrmann	org/dcache/chimera/changelog/changeset-2.14.xml	2016-06-27 15:15:13.509643	32	EXECUTED	7:8b55165b04c65c4cb8ccf7f93fde9faa	sql		\N	3.5.1	\N	\N	7033338983
5	behrmann	org/dcache/chimera/changelog/changeset-2.14.xml	2016-06-27 15:15:13.51696	33	EXECUTED	7:3b105eb3c3546102f65d970ecbfad6a8	createProcedure	use encode on bytea field	\N	3.5.1	\N	\N	7033338983
6.1	behrmann	org/dcache/chimera/changelog/changeset-2.14.xml	2016-06-27 15:15:13.535112	34	EXECUTED	7:513a5a46018019f629edb84999ab9951	createProcedure		\N	3.5.1	\N	\N	7033338983
7	behrmann	org/dcache/chimera/changelog/changeset-2.14.xml	2016-06-27 15:15:13.561901	35	EXECUTED	7:993c78bca18f3243c0a5da7bbdf3e1f7	createProcedure procedureName=f_create_inode		\N	3.5.1	\N	\N	7033338983
8	behrmann	org/dcache/chimera/changelog/changeset-2.14.xml	2016-06-27 15:15:13.606756	36	EXECUTED	7:981ddaa56caaee56284f3a297d6bfc58	createTable tableName=t_tags2; createTable tableName=t_tags_inodes2; sql; sql; sql; sql; dropColumn columnName=itagid_old, tableName=t_tags_inodes2; dropTable tableName=t_tags; dropTable tableName=t_tags_inodes; renameTable newTableName=t_tags, ol...	Change type of itagid to auto incrementing bigint	\N	3.5.1	\N	\N	7033338983
1	behrmann	org/dcache/chimera/changelog/changeset-2.15.xml	2016-06-27 15:15:13.641819	37	EXECUTED	7:2db9e833ae19148780e5d1acc517eaa8	insert tableName=t_inodes; insert tableName=t_dirs; sql	Create lost+found directory	\N	3.5.1	\N	\N	7033338983
2	behrmann	org/dcache/chimera/changelog/changeset-2.15.xml	2016-06-27 15:15:13.645986	38	EXECUTED	7:488b677497845d9fdccc2b4735c955fa	sql	Move lost links to lost+found	\N	3.5.1	\N	\N	7033338983
4	behrmann	org/dcache/chimera/changelog/changeset-2.15.xml	2016-06-27 15:15:13.657705	39	EXECUTED	7:21ed1ac81363f72ec5be2170ce036724	sql	Move unlinked files and directories to lost+found	\N	3.5.1	\N	\N	7033338983
5	behrmann	org/dcache/chimera/changelog/changeset-2.15.xml	2016-06-27 15:15:13.660783	40	EXECUTED	7:d541022e08ac308078ab824a740bb062	sql	Correct link count on directories	\N	3.5.1	\N	\N	7033338983
6	behrmann	org/dcache/chimera/changelog/changeset-2.15.xml	2016-06-27 15:15:13.686648	41	EXECUTED	7:baa9b2ae6dbe27f5188485d2cb3b404a	addColumn tableName=t_inodes; addUniqueConstraint constraintName=i_inodes_inumber, tableName=t_inodes	Add inumber identity field	\N	3.5.1	\N	\N	7033338983
7	behrmann	org/dcache/chimera/changelog/changeset-2.15.xml	2016-06-27 15:15:13.691764	42	EXECUTED	7:5180b29bd71f695580bd05ad34da28bc	createProcedure	Update f_create_inode stored procedure to return inumber	\N	3.5.1	\N	\N	7033338983
8	behrmann	org/dcache/chimera/changelog/changeset-2.15.xml	2016-06-27 15:15:13.721207	43	EXECUTED	7:e303e36cdcbe213f479edb598925d775	renameTable newTableName=t_tags2, oldTableName=t_tags; createTable tableName=t_tags; sql; dropTable tableName=t_tags2; addPrimaryKey constraintName=t_tags_pkey, tableName=t_tags; createIndex indexName=i_tags_itagid, tableName=t_tags; addForeignKey...	Rewrite t_tags to use inumber as foreign key	\N	3.5.1	\N	\N	7033338983
9	behrmann	org/dcache/chimera/changelog/changeset-2.15.xml	2016-06-27 15:15:13.76214	44	EXECUTED	7:73f1f1fc065fba417a14d775ccdfd294	renameTable newTableName=t_dirs_old, oldTableName=t_dirs; createTable tableName=t_dirs; sql; dropTable tableName=t_dirs_old; addPrimaryKey constraintName=t_dirs_pkey, tableName=t_dirs; createIndex indexName=i_dirs_ichild, tableName=t_dirs; addFore...	Replace ipnfsid by inumber as foreign key in t_dirs	\N	3.5.1	\N	\N	7033338983
10	behrmann	org/dcache/chimera/changelog/changeset-2.15.xml	2016-06-27 15:15:13.780292	45	EXECUTED	7:13362e810545e19fb1314971b3a792a7	renameTable newTableName=t_inodes_data2, oldTableName=t_inodes_data; createTable tableName=t_inodes_data; sql; dropTable tableName=t_inodes_data2; addPrimaryKey constraintName=t_inodes_data_pkey, tableName=t_inodes_data; addForeignKeyConstraint ba...	Replace ipndsid by inumber as foreign key in t_inodes_data	\N	3.5.1	\N	\N	7033338983
11	behrmann	org/dcache/chimera/changelog/changeset-2.15.xml	2016-06-27 15:15:13.79697	46	EXECUTED	7:16d92e6ffdfebb8cbcd781060b2bd28d	createProcedure; createProcedure; createProcedure; createProcedure; createProcedure; createProcedure; createProcedure; sql	Update stored procedures for inumber changes in t_dirs	\N	3.5.1	\N	\N	7033338983
12	behrmann	org/dcache/chimera/changelog/changeset-2.15.xml	2016-06-27 15:15:13.814506	47	EXECUTED	7:4e12375b560365cf7e08d0073e17d891	renameTable newTableName=t_inodes_checksum2, oldTableName=t_inodes_checksum; createTable tableName=t_inodes_checksum; sql; dropTable tableName=t_inodes_checksum2; addPrimaryKey constraintName=t_inodes_checksum_pkey, tableName=t_inodes_checksum; ad...	Replace ipndsid by inumber as foreign key in t_inodes_checksum	\N	3.5.1	\N	\N	7033338983
13	behrmann	org/dcache/chimera/changelog/changeset-2.15.xml	2016-06-27 15:15:13.831065	48	EXECUTED	7:ac1f2432f90cbc0e26283b4659dc29e2	renameTable newTableName=t_storageinfo2, oldTableName=t_storageinfo; createTable tableName=t_storageinfo; sql; dropTable tableName=t_storageinfo2; addPrimaryKey constraintName=t_storageinfo_pkey, tableName=t_storageinfo; addForeignKeyConstraint ba...	Replace ipndsid by inumber as foreign key in t_storageinfo	\N	3.5.1	\N	\N	7033338983
15	behrmann	org/dcache/chimera/changelog/changeset-2.15.xml	2016-06-27 15:15:13.860762	49	EXECUTED	7:96b0bfae3af90c9ffad9d0ded811f649	renameTable newTableName=t_locationinfo2, oldTableName=t_locationinfo; createTable tableName=t_locationinfo; sql; dropTable tableName=t_locationinfo2; addPrimaryKey constraintName=t_locationinfo_pkey, tableName=t_locationinfo; addForeignKeyConstra...	Replace ipndsid by inumber as foreign key in t_locationinfo	\N	3.5.1	\N	\N	7033338983
16	behrmann	org/dcache/chimera/changelog/changeset-2.15.xml	2016-06-27 15:15:13.866535	50	EXECUTED	7:0ddcf25f9c8db3c77d2bc9ae94243b69	createProcedure	Update stored procedures for inumber changes in t_locationinfo	\N	3.5.1	\N	\N	7033338983
17	behrmann	org/dcache/chimera/changelog/changeset-2.15.xml	2016-06-27 15:15:13.88475	51	EXECUTED	7:26bbab5e7c0f6ee06e96ee884cc43fb4	renameTable newTableName=t_level_1_old, oldTableName=t_level_1; createTable tableName=t_level_1; sql; dropTable tableName=t_level_1_old; addPrimaryKey constraintName=t_level_1_pkey, tableName=t_level_1; addForeignKeyConstraint baseTableName=t_leve...	Replace ipndsid by inumber as foreign key in t_level_1	\N	3.5.1	\N	\N	7033338983
18	behrmann	org/dcache/chimera/changelog/changeset-2.15.xml	2016-06-27 15:15:13.904516	52	EXECUTED	7:3db30539a9c4af64bcfbf4c96f871048	renameTable newTableName=t_level_2_old, oldTableName=t_level_2; createTable tableName=t_level_2; sql; dropTable tableName=t_level_2_old; addPrimaryKey constraintName=t_level_2_pkey, tableName=t_level_2; addForeignKeyConstraint baseTableName=t_leve...	Replace ipndsid by inumber as foreign key in t_level_2	\N	3.5.1	\N	\N	7033338983
19	behrmann	org/dcache/chimera/changelog/changeset-2.15.xml	2016-06-27 15:15:13.932605	53	EXECUTED	7:c5ffc178c0e360910cda240b2953e61f	renameTable newTableName=t_level_3_old, oldTableName=t_level_3; createTable tableName=t_level_3; sql; dropTable tableName=t_level_3_old; addPrimaryKey constraintName=t_level_3_pkey, tableName=t_level_3; addForeignKeyConstraint baseTableName=t_leve...	Replace ipndsid by inumber as foreign key in t_level_3	\N	3.5.1	\N	\N	7033338983
20	behrmann	org/dcache/chimera/changelog/changeset-2.15.xml	2016-06-27 15:15:13.957619	54	EXECUTED	7:5dd70248d188b08da7c802bd8b3d453b	renameTable newTableName=t_level_4_old, oldTableName=t_level_4; createTable tableName=t_level_4; sql; dropTable tableName=t_level_4_old; addPrimaryKey constraintName=t_level_4_pkey, tableName=t_level_4; addForeignKeyConstraint baseTableName=t_leve...	Replace ipndsid by inumber as foreign key in t_level_4	\N	3.5.1	\N	\N	7033338983
21	behrmann	org/dcache/chimera/changelog/changeset-2.15.xml	2016-06-27 15:15:13.979348	55	EXECUTED	7:fcfded6e1f1683ac1499de1bf5963faf	renameTable newTableName=t_level_5_old, oldTableName=t_level_5; createTable tableName=t_level_5; sql; dropTable tableName=t_level_5_old; addPrimaryKey constraintName=t_level_5_pkey, tableName=t_level_5; addForeignKeyConstraint baseTableName=t_leve...	Replace ipndsid by inumber as foreign key in t_level_5	\N	3.5.1	\N	\N	7033338983
22	behrmann	org/dcache/chimera/changelog/changeset-2.15.xml	2016-06-27 15:15:13.999485	56	EXECUTED	7:f30285a387085849684cb3818cf648b4	renameTable newTableName=t_level_6_old, oldTableName=t_level_6; createTable tableName=t_level_6; sql; dropTable tableName=t_level_6_old; addPrimaryKey constraintName=t_level_6_pkey, tableName=t_level_6; addForeignKeyConstraint baseTableName=t_leve...	Replace ipndsid by inumber as foreign key in t_level_6	\N	3.5.1	\N	\N	7033338983
23	behrmann	org/dcache/chimera/changelog/changeset-2.15.xml	2016-06-27 15:15:14.016002	57	EXECUTED	7:4286e635a0f48d0e5c451dfd359aea86	renameTable newTableName=t_level_7_old, oldTableName=t_level_7; createTable tableName=t_level_7; sql; dropTable tableName=t_level_7_old; addPrimaryKey constraintName=t_level_7_pkey, tableName=t_level_7; addForeignKeyConstraint baseTableName=t_leve...	Replace ipndsid by inumber as foreign key in t_level_7	\N	3.5.1	\N	\N	7033338983
24.1	litvinse	org/dcache/chimera/changelog/changeset-2.15.xml	2016-06-27 15:15:14.031304	58	EXECUTED	7:035e5de6a95c0d04e10434fa44e44f61	createProcedure; createProcedure	Fix trigger on insert or update on t_level_4	\N	3.5.1	\N	\N	7033338983
25	behrmann	org/dcache/chimera/changelog/changeset-2.15.xml	2016-06-27 15:15:14.049213	59	EXECUTED	7:f2b4f1268cebeb5237c05275ad6ee716	renameTable newTableName=t_acl2, oldTableName=t_acl; createTable tableName=t_acl; sql; dropTable tableName=t_acl2; addPrimaryKey constraintName=t_acl_pkey, tableName=t_acl; addForeignKeyConstraint baseTableName=t_acl, constraintName=t_acl_fkey, re...	Replace ipndsid by inumber as foreign key in t_acl	\N	3.5.1	\N	\N	7033338983
\.


--
-- Data for Name: databasechangeloglock; Type: TABLE DATA; Schema: public; Owner: chimera
--

COPY databasechangeloglock (id, locked, lockgranted, lockedby) FROM stdin;
1	f	\N	\N
\.


--
-- Data for Name: t_acl; Type: TABLE DATA; Schema: public; Owner: chimera
--

COPY t_acl (inumber, ace_order, rs_type, type, access_msk, who, who_id, flags) FROM stdin;
\.


--
-- Data for Name: t_dirs; Type: TABLE DATA; Schema: public; Owner: chimera
--

COPY t_dirs (iparent, ichild, iname) FROM stdin;
1	2	lost+found
1	4	pnfs
4	5	desy.de
5	6	exfel
\.


--
-- Data for Name: t_groups; Type: TABLE DATA; Schema: public; Owner: chimera
--

COPY t_groups (id, group_name) FROM stdin;
\.


--
-- Data for Name: t_inodes; Type: TABLE DATA; Schema: public; Owner: chimera
--

COPY t_inodes (ipnfsid, itype, imode, inlink, iuid, igid, isize, iio, ictime, iatime, imtime, icrtime, igeneration, iaccess_latency, iretention_policy, inumber) FROM stdin;
000000000000000000000000000000000001	16384	700	2	0	0	512	0	2016-06-27 15:15:13.637938	2016-06-27 15:15:13.637938	2016-06-27 15:15:13.637938	2016-06-27 15:15:13.637938	0	\N	\N	2
00004870C05FA30E4BAFAF6421F9DA37428A	16384	493	3	65534	65534	512	0	2016-07-26 07:33:24.799	2016-07-26 07:33:24.732	2016-07-26 07:33:24.799	2016-07-26 07:33:24.732	1	\N	\N	4
0000E8A4F50D33A7489CAA50122A79A42D45	16384	493	2	65534	65534	512	0	2016-07-26 07:33:24.838	2016-07-26 07:33:24.838	2016-07-26 07:33:24.838	2016-07-26 07:33:24.838	0	\N	\N	6
0000A0E11D0E630C4543A9B867A17234EEC4	16384	493	3	65534	65534	512	0	2016-07-26 07:33:24.838	2016-07-26 07:33:24.799	2016-07-26 07:33:24.838	2016-07-26 07:33:24.799	1	\N	\N	5
000000000000000000000000000000000000	16384	511	4	0	0	512	0	2016-07-26 07:33:29.664	2016-06-27 15:15:12.630086	2016-07-26 07:33:29.664	2016-06-27 15:15:12.630086	3	\N	\N	1
\.


--
-- Data for Name: t_inodes_checksum; Type: TABLE DATA; Schema: public; Owner: chimera
--

COPY t_inodes_checksum (inumber, itype, isum) FROM stdin;
\.


--
-- Data for Name: t_inodes_data; Type: TABLE DATA; Schema: public; Owner: chimera
--

COPY t_inodes_data (inumber, ifiledata) FROM stdin;
\.


--
-- Name: t_inodes_inumber_seq; Type: SEQUENCE SET; Schema: public; Owner: chimera
--

SELECT pg_catalog.setval('t_inodes_inumber_seq', 6, true);


--
-- Data for Name: t_level_1; Type: TABLE DATA; Schema: public; Owner: chimera
--

COPY t_level_1 (inumber, imode, inlink, iuid, igid, isize, ictime, iatime, imtime, ifiledata) FROM stdin;
\.


--
-- Data for Name: t_level_2; Type: TABLE DATA; Schema: public; Owner: chimera
--

COPY t_level_2 (inumber, imode, inlink, iuid, igid, isize, ictime, iatime, imtime, ifiledata) FROM stdin;
\.


--
-- Data for Name: t_level_3; Type: TABLE DATA; Schema: public; Owner: chimera
--

COPY t_level_3 (inumber, imode, inlink, iuid, igid, isize, ictime, iatime, imtime, ifiledata) FROM stdin;
\.


--
-- Data for Name: t_level_4; Type: TABLE DATA; Schema: public; Owner: chimera
--

COPY t_level_4 (inumber, imode, inlink, iuid, igid, isize, ictime, iatime, imtime, ifiledata) FROM stdin;
\.


--
-- Data for Name: t_level_5; Type: TABLE DATA; Schema: public; Owner: chimera
--

COPY t_level_5 (inumber, imode, inlink, iuid, igid, isize, ictime, iatime, imtime, ifiledata) FROM stdin;
\.


--
-- Data for Name: t_level_6; Type: TABLE DATA; Schema: public; Owner: chimera
--

COPY t_level_6 (inumber, imode, inlink, iuid, igid, isize, ictime, iatime, imtime, ifiledata) FROM stdin;
\.


--
-- Data for Name: t_level_7; Type: TABLE DATA; Schema: public; Owner: chimera
--

COPY t_level_7 (inumber, imode, inlink, iuid, igid, isize, ictime, iatime, imtime, ifiledata) FROM stdin;
\.


--
-- Data for Name: t_locationinfo; Type: TABLE DATA; Schema: public; Owner: chimera
--

COPY t_locationinfo (inumber, itype, ipriority, ictime, iatime, istate, ilocation) FROM stdin;
\.


--
-- Data for Name: t_locationinfo_trash; Type: TABLE DATA; Schema: public; Owner: chimera
--

COPY t_locationinfo_trash (ipnfsid, itype, ilocation, ipriority, ictime, iatime, istate) FROM stdin;
00007BF09A4E00A34074A36712C18FC85B49	2		0	2016-07-26 07:32:56.554783	2016-07-26 07:32:56.554783	1
\.


--
-- Data for Name: t_storageinfo; Type: TABLE DATA; Schema: public; Owner: chimera
--

COPY t_storageinfo (inumber, ihsmname, istoragegroup, istoragesubgroup) FROM stdin;
\.


--
-- Data for Name: t_tags; Type: TABLE DATA; Schema: public; Owner: chimera
--

COPY t_tags (inumber, itagid, isorign, itagname) FROM stdin;
\.


--
-- Data for Name: t_tags_inodes; Type: TABLE DATA; Schema: public; Owner: chimera
--

COPY t_tags_inodes (itagid, imode, inlink, iuid, igid, isize, ictime, iatime, imtime, ivalue) FROM stdin;
\.


--
-- Name: t_tags_inodes2_itagid_seq; Type: SEQUENCE SET; Schema: public; Owner: chimera
--

SELECT pg_catalog.setval('t_tags_inodes2_itagid_seq', 1, false);


--
-- Name: i_inodes_inumber; Type: CONSTRAINT; Schema: public; Owner: chimera
--

ALTER TABLE ONLY t_inodes
    ADD CONSTRAINT i_inodes_inumber UNIQUE (inumber);


--
-- Name: pk_databasechangeloglock; Type: CONSTRAINT; Schema: public; Owner: chimera
--

ALTER TABLE ONLY databasechangeloglock
    ADD CONSTRAINT pk_databasechangeloglock PRIMARY KEY (id);


--
-- Name: t_acl_pkey; Type: CONSTRAINT; Schema: public; Owner: chimera
--

ALTER TABLE ONLY t_acl
    ADD CONSTRAINT t_acl_pkey PRIMARY KEY (inumber, ace_order);


--
-- Name: t_dirs_pkey; Type: CONSTRAINT; Schema: public; Owner: chimera
--

ALTER TABLE ONLY t_dirs
    ADD CONSTRAINT t_dirs_pkey PRIMARY KEY (iparent, iname);


--
-- Name: t_groups_pkey; Type: CONSTRAINT; Schema: public; Owner: chimera
--

ALTER TABLE ONLY t_groups
    ADD CONSTRAINT t_groups_pkey PRIMARY KEY (id);


--
-- Name: t_inodes_checksum_pkey; Type: CONSTRAINT; Schema: public; Owner: chimera
--

ALTER TABLE ONLY t_inodes_checksum
    ADD CONSTRAINT t_inodes_checksum_pkey PRIMARY KEY (inumber, itype);


--
-- Name: t_inodes_data_pkey; Type: CONSTRAINT; Schema: public; Owner: chimera
--

ALTER TABLE ONLY t_inodes_data
    ADD CONSTRAINT t_inodes_data_pkey PRIMARY KEY (inumber);


--
-- Name: t_inodes_pkey; Type: CONSTRAINT; Schema: public; Owner: chimera
--

ALTER TABLE ONLY t_inodes
    ADD CONSTRAINT t_inodes_pkey PRIMARY KEY (ipnfsid);

ALTER TABLE t_inodes CLUSTER ON t_inodes_pkey;


--
-- Name: t_level_1_pkey; Type: CONSTRAINT; Schema: public; Owner: chimera
--

ALTER TABLE ONLY t_level_1
    ADD CONSTRAINT t_level_1_pkey PRIMARY KEY (inumber);


--
-- Name: t_level_2_pkey; Type: CONSTRAINT; Schema: public; Owner: chimera
--

ALTER TABLE ONLY t_level_2
    ADD CONSTRAINT t_level_2_pkey PRIMARY KEY (inumber);


--
-- Name: t_level_3_pkey; Type: CONSTRAINT; Schema: public; Owner: chimera
--

ALTER TABLE ONLY t_level_3
    ADD CONSTRAINT t_level_3_pkey PRIMARY KEY (inumber);


--
-- Name: t_level_4_pkey; Type: CONSTRAINT; Schema: public; Owner: chimera
--

ALTER TABLE ONLY t_level_4
    ADD CONSTRAINT t_level_4_pkey PRIMARY KEY (inumber);


--
-- Name: t_level_5_pkey; Type: CONSTRAINT; Schema: public; Owner: chimera
--

ALTER TABLE ONLY t_level_5
    ADD CONSTRAINT t_level_5_pkey PRIMARY KEY (inumber);


--
-- Name: t_level_6_pkey; Type: CONSTRAINT; Schema: public; Owner: chimera
--

ALTER TABLE ONLY t_level_6
    ADD CONSTRAINT t_level_6_pkey PRIMARY KEY (inumber);


--
-- Name: t_level_7_pkey; Type: CONSTRAINT; Schema: public; Owner: chimera
--

ALTER TABLE ONLY t_level_7
    ADD CONSTRAINT t_level_7_pkey PRIMARY KEY (inumber);


--
-- Name: t_locationinfo_pkey; Type: CONSTRAINT; Schema: public; Owner: chimera
--

ALTER TABLE ONLY t_locationinfo
    ADD CONSTRAINT t_locationinfo_pkey PRIMARY KEY (inumber, itype, ilocation);


--
-- Name: t_locationinfo_trash_pkey; Type: CONSTRAINT; Schema: public; Owner: chimera
--

ALTER TABLE ONLY t_locationinfo_trash
    ADD CONSTRAINT t_locationinfo_trash_pkey PRIMARY KEY (ipnfsid, itype, ilocation);


--
-- Name: t_storageinfo_pkey; Type: CONSTRAINT; Schema: public; Owner: chimera
--

ALTER TABLE ONLY t_storageinfo
    ADD CONSTRAINT t_storageinfo_pkey PRIMARY KEY (inumber);


--
-- Name: t_tags_inodes_pkey; Type: CONSTRAINT; Schema: public; Owner: chimera
--

ALTER TABLE ONLY t_tags_inodes
    ADD CONSTRAINT t_tags_inodes_pkey PRIMARY KEY (itagid);


--
-- Name: t_tags_pkey; Type: CONSTRAINT; Schema: public; Owner: chimera
--

ALTER TABLE ONLY t_tags
    ADD CONSTRAINT t_tags_pkey PRIMARY KEY (inumber, itagname);


--
-- Name: i_dirs_ichild; Type: INDEX; Schema: public; Owner: chimera
--

CREATE INDEX i_dirs_ichild ON t_dirs USING btree (ichild);


--
-- Name: i_locationinfo_trash_itype_ilocation; Type: INDEX; Schema: public; Owner: chimera
--

CREATE INDEX i_locationinfo_trash_itype_ilocation ON t_locationinfo_trash USING btree (itype, ilocation);


--
-- Name: i_tags_itagid; Type: INDEX; Schema: public; Owner: chimera
--

CREATE INDEX i_tags_itagid ON t_tags USING btree (itagid);


--
-- Name: tgr_enstore_location; Type: TRIGGER; Schema: public; Owner: chimera
--

CREATE TRIGGER tgr_enstore_location BEFORE INSERT OR UPDATE ON t_level_4 FOR EACH ROW EXECUTE PROCEDURE f_enstorelevel2locationinfo();


--
-- Name: tgr_locationinfo_trash; Type: TRIGGER; Schema: public; Owner: chimera
--

CREATE TRIGGER tgr_locationinfo_trash BEFORE DELETE ON t_inodes FOR EACH ROW EXECUTE PROCEDURE f_locationinfo2trash();


--
-- Name: t_acl_fkey; Type: FK CONSTRAINT; Schema: public; Owner: chimera
--

ALTER TABLE ONLY t_acl
    ADD CONSTRAINT t_acl_fkey FOREIGN KEY (inumber) REFERENCES t_inodes(inumber) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: t_dirs_ichild_fkey; Type: FK CONSTRAINT; Schema: public; Owner: chimera
--

ALTER TABLE ONLY t_dirs
    ADD CONSTRAINT t_dirs_ichild_fkey FOREIGN KEY (ichild) REFERENCES t_inodes(inumber) ON UPDATE CASCADE;


--
-- Name: t_dirs_iparent_fkey; Type: FK CONSTRAINT; Schema: public; Owner: chimera
--

ALTER TABLE ONLY t_dirs
    ADD CONSTRAINT t_dirs_iparent_fkey FOREIGN KEY (iparent) REFERENCES t_inodes(inumber) ON UPDATE CASCADE;


--
-- Name: t_inodes_checksum_inumber_fkey; Type: FK CONSTRAINT; Schema: public; Owner: chimera
--

ALTER TABLE ONLY t_inodes_checksum
    ADD CONSTRAINT t_inodes_checksum_inumber_fkey FOREIGN KEY (inumber) REFERENCES t_inodes(inumber) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: t_inodes_data_inumber_fkey; Type: FK CONSTRAINT; Schema: public; Owner: chimera
--

ALTER TABLE ONLY t_inodes_data
    ADD CONSTRAINT t_inodes_data_inumber_fkey FOREIGN KEY (inumber) REFERENCES t_inodes(inumber) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: t_level_1_inumber_fkey; Type: FK CONSTRAINT; Schema: public; Owner: chimera
--

ALTER TABLE ONLY t_level_1
    ADD CONSTRAINT t_level_1_inumber_fkey FOREIGN KEY (inumber) REFERENCES t_inodes(inumber) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: t_level_2_inumber_fkey; Type: FK CONSTRAINT; Schema: public; Owner: chimera
--

ALTER TABLE ONLY t_level_2
    ADD CONSTRAINT t_level_2_inumber_fkey FOREIGN KEY (inumber) REFERENCES t_inodes(inumber) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: t_level_3_inumber_fkey; Type: FK CONSTRAINT; Schema: public; Owner: chimera
--

ALTER TABLE ONLY t_level_3
    ADD CONSTRAINT t_level_3_inumber_fkey FOREIGN KEY (inumber) REFERENCES t_inodes(inumber) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: t_level_4_inumber_fkey; Type: FK CONSTRAINT; Schema: public; Owner: chimera
--

ALTER TABLE ONLY t_level_4
    ADD CONSTRAINT t_level_4_inumber_fkey FOREIGN KEY (inumber) REFERENCES t_inodes(inumber) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: t_level_5_inumber_fkey; Type: FK CONSTRAINT; Schema: public; Owner: chimera
--

ALTER TABLE ONLY t_level_5
    ADD CONSTRAINT t_level_5_inumber_fkey FOREIGN KEY (inumber) REFERENCES t_inodes(inumber) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: t_level_6_inumber_fkey; Type: FK CONSTRAINT; Schema: public; Owner: chimera
--

ALTER TABLE ONLY t_level_6
    ADD CONSTRAINT t_level_6_inumber_fkey FOREIGN KEY (inumber) REFERENCES t_inodes(inumber) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: t_level_7_inumber_fkey; Type: FK CONSTRAINT; Schema: public; Owner: chimera
--

ALTER TABLE ONLY t_level_7
    ADD CONSTRAINT t_level_7_inumber_fkey FOREIGN KEY (inumber) REFERENCES t_inodes(inumber) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: t_locationinfo_inumber_fkey; Type: FK CONSTRAINT; Schema: public; Owner: chimera
--

ALTER TABLE ONLY t_locationinfo
    ADD CONSTRAINT t_locationinfo_inumber_fkey FOREIGN KEY (inumber) REFERENCES t_inodes(inumber) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: t_storageinfo_inumber_fkey; Type: FK CONSTRAINT; Schema: public; Owner: chimera
--

ALTER TABLE ONLY t_storageinfo
    ADD CONSTRAINT t_storageinfo_inumber_fkey FOREIGN KEY (inumber) REFERENCES t_inodes(inumber) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: t_tags_inumber_fkey; Type: FK CONSTRAINT; Schema: public; Owner: chimera
--

ALTER TABLE ONLY t_tags
    ADD CONSTRAINT t_tags_inumber_fkey FOREIGN KEY (inumber) REFERENCES t_inodes(inumber) ON UPDATE CASCADE;


--
-- Name: t_tags_itagid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: chimera
--

ALTER TABLE ONLY t_tags
    ADD CONSTRAINT t_tags_itagid_fkey FOREIGN KEY (itagid) REFERENCES t_tags_inodes(itagid) ON UPDATE CASCADE;


--
-- Name: public; Type: ACL; Schema: -; Owner: postgres
--

REVOKE ALL ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON SCHEMA public FROM postgres;
GRANT ALL ON SCHEMA public TO postgres;
GRANT ALL ON SCHEMA public TO PUBLIC;


--
-- PostgreSQL database dump complete
--

