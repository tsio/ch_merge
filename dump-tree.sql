--
-- simple dump for a subtree
--

create or replace function dumptree(varchar, varchar) returns void as $$
declare
  root varchar := $1;
  indent varchar :=$2;
  subdirs RECORD;
begin
  for subdirs in select t_inodes.ipnfsid, t_dirs.iname from t_inodes, t_dirs where t_inodes.itype=16384 and t_dirs.iparent=root and t_inodes.ipnfsid=t_dirs.ipnfsid and t_dirs.iname not in ('.', '..') loop
      begin
          raise notice '%|-%.', indent, subdirs.iname;
          perform dumptree(subdirs.ipnfsid, indent || indent);
      end;
  end loop;

end;
$$
language 'plpgsql';



create or replace function push_tag(varchar, varchar) returns void as $$
declare
  root varchar := $1;
  tag varchar := $2;
  subdirs RECORD;
  tagid varchar;
begin

  select into tagid itagid from t_tags where ipnfsid = root and itagname = tag;

  for subdirs in select t_inodes.ipnfsid, t_dirs.iname from t_inodes, t_dirs where t_inodes.itype=16384 and t_dirs.iparent=root and t_inodes.ipnfsid=t_dirs.ipnfsid and t_dirs.iname not in ('.', '..') loop
      begin
          delete from t_tags where ipnfsid = subdirs.ipnfsid and itagname = tag;
          insert into t_tags values (subdirs.ipnfsid, tag, tagid, 0);
          perform push_tag(subdirs.ipnfsid, tag);
      end;
  end loop;

end;
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION remove_tag(varchar, varchar) returns void as $$
DECLARE
  root varchar := $1;
  tag varchar := $2;
  subdirs RECORD;
  tagid varchar;
  n int;
BEGIN

    -- get tagid
    SELECT INTO tagid itagid FROM t_tags WHERE ipnfsid = root AND itagname = tag;

    -- delete tag in this directory
    DELETE FROM t_tags WHERE ipnfsid = root AND itagname = tag;

    -- do the same for all subdirs
    FOR subdirs IN SELECT t_inodes.ipnfsid, t_dirs.iname FROM t_inodes, t_dirs WHERE t_inodes.itype=16384 AND t_dirs.iparent=root AND t_inodes.ipnfsid=t_dirs.ipnfsid LOOP
        BEGIN
            PERFORM remove_tag(subdirs.ipnfsid, tag);
        END;
    END LOOP;

    -- remove tag it there are no references to it
    SELECT INTO n COUNT(*) FROM t_tags WHERE itagid = tagid;
    IF n = 0 THEN
        DELETE FROM t_tags_inodes WHERE itagid = tagid;
    END IF;

END;
$$
language 'plpgsql';


CREATE OR REPLACE FUNCTION remove_tag215(bigint, varchar) returns void as $$
DECLARE
  root bigint := $1;
  tag varchar := $2;
  subdirs RECORD;
  tagid bigint;
  n int;
BEGIN

    -- get tagid
    SELECT INTO tagid itagid from t_tags where inumber = root and itagname = tag;

    -- delete tag in this directory
    DELETE FROM t_tags where inumber = root and itagname = tag;

    -- do the same for all subdirs
    FOR subdirs IN SELECT t_inodes.inumber, t_dirs.iname FROM t_inodes, t_dirs WHERE t_inodes.itype=16384 AND t_dirs.iparent=root AND t_inodes.inumber=t_dirs.ichild LOOP
        BEGIN
            PERFORM remove_tag(subdirs.inumber, tag);
        END;
    END LOOP;

    -- remove tag it there are no references to it
    SELECT INTO n COUNT(*) FROM t_tags WHERE itagid = tagid;
    IF n = 0 THEN
        DELETE FROM t_tags_inodes where itagid = tagid;
    END IF;

END;
$$
language 'plpgsql';

create or replace function push_tag215(bigint, varchar) returns void as $$
declare
  root bigint := $1;
  tag varchar := $2;
  subdirs RECORD;
  tagid bigint;
begin

  select into tagid itagid from t_tags where inumber = root and itagname = tag;

  for subdirs in select t_inodes.inumber, t_dirs.iname from t_inodes, t_dirs where t_inodes.itype=16384 and t_dirs.iparent=root and t_inodes.inumber=t_dirs.ichild loop
      begin
          delete from t_tags where inumber = subdirs.inumber and itagname = tag;
          insert into t_tags values (subdirs.inumber, tagid, 0, tag);
          perform push_tag(subdirs.inumber, tag);
      end;
  end loop;
end;
$$
language 'plpgsql';
