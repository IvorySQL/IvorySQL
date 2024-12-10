--test ok
--print 10 and 121
do $$
declare
  mds integer;
  originial integer;
  function square(original integer) return integer;
  function square(original integer) return integer
  AS
  declare
       original_squared integer;
  begin
       original_squared := original * original;
       return original_squared;
   end;
begin
    mds := 10;
    raise info '%',mds;
    originial := 11;
    mds := square(originial);
    raise info '%',mds;
end;$$ language plisql;

--test ok
create or replace function test_subproc_func(a in integer) returns integer as
$$
declare
  mds integer;
  original integer;
  function square(original in integer) return integer;
  function square(original in integer) return integer
  AS
  declare
       original_squared integer;
  begin
       original_squared := original * original;
       original := original_squared + 1;
       return original_squared;
   end;
begin
    mds := 10;
    original := square(mds);
    raise info '%',original;
    a := original + 1;
    return mds;
end;$$ language plisql;
/

--print 100 and 10
select * from test_subproc_func(23);
drop function test_subproc_func(integer);

--test the var in different block ok
--print 23 45 529
do $$
declare
  var1 integer;
  function square(original integer) return integer;
  function square(original integer) return integer
  AS
  declare
       original_squared integer;
       var1 integer;
  begin
       var1 := 45;
       original_squared := original * original;
       raise info '%',var1;
       return original_squared;
   end;
begin
    var1 := 23;
    raise info '%',var1;
    var1 := square(var1);
    raise info '%', var1;
end; $$ language plisql;

--test failed
do $$
declare
  var1 integer;
  function square(original integer) return integer;
begin
    function square(original integer) return integer
    AS
    declare
       original_squared integer;
       var1 integer;
  begin
       var1 := 45;
       original_squared := original * original;
       raise info '%',var1;
       return original_squared;
   end;
    var1 := 23;
    raise info '%',var1;
 end;$$ language plisql;

--test ok
--print 23 45 55 65 529
do $$
declare
  var1 integer;
  function square(original integer) return integer;
  function square(original integer) return integer
  AS
  declare
       original_squared integer;
       var1 integer;
       function test(test integer) return integer
       AS
       declare
          var1 integer;
	      var2 integer;
       begin
           var1 := 55;
	   raise info '%',var1;
           var2 := var1 + 10;
	   return var2;
       end;
  begin
       var1 := 45;
       original_squared := original * original;
       raise info '%',var1;
       var1 := test(var1);
       raise info '%', var1;
       return original_squared;
   end;
begin
    var1 := 23;
    raise info '%',var1;
    var1 := square(var1);
    raise info '%', var1;
 end;$$ language plisql;

--test ok
do $$
declare
  mds integer;
  function test1(id integer) return integer IS
  declare
     mds integer;
  begin
       mds := 1;
       return mds;
  end;
  function test2(id integer) return integer AS
  declare
      mds integer;
   begin
      mds := 2;
      return mds;
   end;
begin
   mds := 3;
END;$$ language plisql;

--test ok
--print 45 529 529 529
do $$
declare
  var1 integer;
  function square(original integer) return integer AS
  begin
    return original;
  end;
begin
   declare
      function square(original integer) return integer
      AS
      declare
         original_squared integer;
         var1 integer;
      begin
         var1 := 45;
         original_squared := original * original;
         raise info '%', var1;
         return original_squared;
     end;
   begin
      var1 := 23;
      var1 := square(var1);
      raise info '%',var1;
   end;
   raise info '%', var1;
   var1 := square(var1);
   raise info '%',var1;
 end;$$ language plisql;

--subproc use global variable
--print we are in main function
--res = 45 a square function assign 11
--
--there originial not like oracle
--for out argmuments
do $$
declare
  mds varchar(256);
  originial integer;
  res integer;
  function square(original in out integer) return integer;
  function square(original in out integer) return integer
  AS
  declare
       original_squared integer;
  begin
       original_squared := original * original;
       raise info '%', mds;
       mds := 'a square function assign';
       original := 45;
       --return original_squared;
   end;
begin
    mds := 'we are in main function';
    originial := 11;
    res := square(originial);
    raise info 'res=%',res;
    raise info '%',mds;
    raise info 'originial=%', originial;
end;$$ language plisql;

--test function reload
--test failed
do $$
declare
  name varchar(23);
  id integer;
  function test(id integer) return integer
  as
  begin
       raise info '%',id;
       return id;
   end;
  function test(name integer) return varchar AS
  declare
     name2 varchar(256);
  begin
         raise info '%',name;
	 name2 := 'xiexie';
	 return name2;
  end;
begin
     name := test(23);
     id := test(23);
 END; $$ language plisql;

--test ok
--print 24 xiexie 23 id=23
do $$
declare
  name varchar(23);
  id integer;
  function test(id integer) return integer
  as
  begin
       raise info '%',id;
       return id;
   end;
  function test(name integer) return varchar AS
  declare
     name2 varchar(256);
  begin
         raise info '%',name;
	 name2 := 'xiexie';
	 return name2;
  end;
begin
     name := test(name=>24);
     raise info 'name=%',name;
     id := test(id=>23);
     raise info 'id=%',id;
 end;$$ language plisql;

--test ok
--print 23 23
do $$
declare
  name varchar(23);
  id integer;
  function test(id integer) return integer;
  function test(name integer) return varchar;
  function test(id integer) return integer
  as
  begin
       raise info '%',id;
       return id;
   end;
  function test(name integer) return varchar AS
  declare
     name2 varchar(256);
  begin
         raise info '%', name;
	 name2 := 'xiexie';
	 return name2;
  end;
begin
     name := test(name=>23);
     id := test(id=>23);
end;$$ language plisql;

 --reload argument number
 --test ok
 --print 23 23
do $$
declare
  name varchar(23);
  id integer;
  function test(id integer,name varchar) return integer
  as
  begin
       raise info '%',id;
       return id;
   end;
  function test(name integer) return varchar AS
  declare
     name2 varchar(256);
  begin
         raise info '%',name;
	 name2 := 'xiexie';
	 return name2;
  end;
begin
     name := test(23);
     id := test(23,name);
end;$$ language plisql;

--test ok
--print 23 23 xiexie
do $$
declare
  name varchar(23);
  id integer;
  function test(id integer,name varchar) return integer
  as
  begin
       raise info '%',id;
       raise info '%',name;
       return id;
   end;
  function test(name integer) return varchar AS
  declare
     name2 varchar(256);
  begin
         raise info '%',name;
	 name2 := 'xiexie';
	 return name2;
  end;
begin
     name := test(23);
     id := test(name=>name,id=>23);
end;$$ language plisql;

 --test failed for different return type
 do $$
 declare
  name varchar(23);
  id integer;
  function test(name integer) return integer
  as
  begin
       raise info '%',name;
       return 23;
   end;
  function test(name integer) return varchar as
  begin
         raise info '%',name;
	 return 'beijing';
  end;
begin
     name := test(23);
     id := test(23);
end;$$ language plisql;

--no reference is ok
--print ok
do $$
 declare
  name varchar(23);
  id integer;
  function test(name integer) return integer
  as
  begin
       raise info '%',name;
       return 23;
   end;
  function test(name integer) return varchar as
  begin
         raise info '%',name;
	 return 'beijing';
  end;
begin
     raise info 'ok';
end;$$ language plisql;

--test procedure reload ok
--print 23 xiexie
do $$
declare
  name varchar(23);
  id integer;
  procedure test(name varchar);
  procedure test(name integer);
  procedure test(name varchar)
  as
  begin
       raise info '%', name;
   end;
  procedure test(name integer) as
  begin
         raise info '%', name;
  end;
begin
     name := 'xiexie';
     test(23);
     test(name);
end;$$ language plisql;

-- test subproc function'argument has default value
--test ok
--print 529
do $$
declare
  ret integer;
  function square(original integer default 10) return integer;
  function square(original integer default 10) return integer
  AS
  declare
       original_squared integer;
  begin
       original_squared := original * original;
       return original_squared;
   end;
begin
    ret = square(23);
    raise info '%', ret;
end; $$ language plisql;

 --test ok
 --print 100
do $$
declare
  ret integer;
  function square(original integer default 10) return integer;
  function square(original integer default 10) return integer
  AS
  declare
       original_squared integer;
  begin
       original_squared := original * original;
       return original_squared;
   end;
begin
    ret = square();
    raise info '%', ret;
 end; $$ language plisql;

--test ok
--print 529 100
do $$
declare
  b integer;
  ret integer;
  function square(original integer default b) return integer;
  function square(original integer default b) return integer
  AS
  declare
       original_squared integer;
  begin
       original_squared := original * original;
       return original_squared;
   end;
begin
    b := 23;
    ret := square();
    raise info '%', ret;
    b := 10;
    ret := square();
    raise info '%', ret;
end;$$ language plisql;

--test ok
--print 144
do $$
declare
   ret integer;
  function square(original integer default 10,mds integer) return integer;
  function square(original integer default 10, mds integer) return integer
  AS
  declare
       original_squared integer;
  begin
       original_squared := original * original;
       return original_squared;
   end;
begin
    ret := square(12,23);
    raise info '%', ret;
end; $$ language plisql;

--test failed
do $$
declare
   ret integer;
  function square(original integer default 10,mds integer) return integer;
  function square(original integer default 10, mds integer) return integer
  AS
  declare
       original_squared integer;
  begin
       original_squared := original * original;
       return original_squared;
   end;
begin
    ret := square(23);
    raise info '%', ret;
end; $$ language plisql;

 --test ok
 --print 100
 do $$
 declare
  ret integer;
  function square(original integer default 10,mds integer) return integer;
  function square(original integer default 10, mds integer) return integer
  AS
  declare
       original_squared integer;
  begin
       original_squared := original * original;
       return original_squared;
   end;
begin
    ret := square(mds=>23);
    raise info '%', ret;
end; $$ language plisql;

--test failed
do $$
declare
  ret integer;
  function square(original integer,mds integer default 10) return integer;
  function square(original integer, mds integer default 10) return integer
  AS
  declare
       original_squared integer;
  begin
       original_squared := original * original + mds;
       return original_squared;
   end;
begin
    ret := square(mds=>23);
    raise info '%', ret;
 end;$$ language plisql;

 --test ok
 --print 539
 do $$
 declare
  ret integer;
  function square(original integer,mds integer default 10) return integer;
  function square(original integer, mds integer default 10) return integer
  AS
  declare
       original_squared integer;
  begin
       original_squared := original * original + mds;
       return original_squared;
   end;
begin
    ret := square(original=>23);
    raise info '%', ret;
 end; $$ language plisql;

 --test ok
 --print 539
do $$
declare
  ret integer;
  function square(original integer,mds integer default 10) return integer;
  function square(original integer, mds integer default 10) return integer
  AS
  declare
       original_squared integer;
  begin
       original_squared := original * original + mds;
       return original_squared;
   end;
begin
    ret := square(23);
    raise info '%', ret;
 end; $$ language plisql;

 --test ok
 --print 23 10 24 xiexie 100
 do $$
 declare
  ret integer;
  function square(mds integer,original integer default 10,mdss integer, md2 varchar default 'xiexie') return integer;
  function square(mds integer,original integer default 10, mdss integer, md2 varchar default 'xiexie') return integer
  AS
  declare
       original_squared integer;
  begin
       raise info 'mds=%', mds;
       raise info 'original=%', original;
       raise info 'mdss=%', mdss;
       raise info 'md2=%', md2;
       original_squared := original * original;
       return original_squared;
   end;
begin
    ret := square(mds=>23, mdss=>24);
    raise info '%', ret;
 end; $$ language plisql;

 ---test failed
do $$
declare
  ret integer;
  function square(mds integer,original integer default 10,mdss integer, md2 varchar default 'xiexie') return integer;
  function square(mds integer,original integer default 10, mdss integer, md2 varchar default 'xiexie') return integer
  AS
  declare
       original_squared integer;
  begin
       raise info 'mds=%', mds;
       raise info 'original=%', original;
       raise info 'mdss=%', mdss;
       raise info 'md2=%', md2;
       original_squared := original * original;
       return original_squared;
   end;
begin
    ret := square(23,24);
    raise info '%', ret;
 end; $$ language plisql;

 --test type exchange
 --test ok
 --print float mds2=24 529
 do $$
 declare
  ret integer;
  function square(mds integer, mds2 varchar) return integer;
  function square(mds integer, mds2 float) return integer;
  function square(mds integer, mds2 varchar) return integer
  AS
  declare
       original_squared integer;
  begin
       raise info 'varchar mds2=%', mds2;
       original_squared := mds * mds;
       return original_squared;
   end;
  function square(mds integer, mds2 float) return integer
  AS
  declare
       original_squared integer;
  begin
       raise info 'float mds2=%', mds2;
       original_squared := mds * mds;
       return original_squared;
   end;
begin
    ret := square(23,24);
    raise info '%', ret;
end; $$ language plisql;

--test ok
--print float mds2=24 529
do $$
declare
  ret integer;
  function square(mds integer, mds2 int8) return integer;
  function square(mds integer, mds2 float) return integer;
  function square(mds integer, mds2 int8) return integer
  AS
  declare
       original_squared integer;
  begin
       raise info 'int8 mds2=%', mds2;
       original_squared := mds * mds;
       return original_squared;
   end;
  function square(mds integer, mds2 float) return integer
  AS
  declare
       original_squared integer;
  begin
       raise info 'float mds2=%', mds2;
       original_squared := mds * mds;
       return original_squared;
   end;
begin
    ret := square(23,24);
    raise info '%', ret;
end; $$ language plisql;

 --test ok
 --print text mds2=abc 529
 do $$
 declare
  ret integer;
  function square(mds integer, mds2 varchar) return integer;
  function square(mds integer, mds2 char) return integer;
  function square(mds integer, mds2 text) return integer;
  function square(mds integer, mds2 text) return integer
  AS
  declare
       original_squared integer;
  begin
       raise info 'text mds2=%', mds2;
       original_squared := mds * mds;
       return original_squared;
   end;
  function square(mds integer, mds2 varchar) return integer
  AS
  declare
       original_squared integer;
  begin
       raise info 'varchar mds2=%', mds2;
       original_squared := mds * mds;
       return original_squared;
   end;
  function square(mds integer, mds2 char) return integer
  AS
  declare
       original_squared integer;
  begin
       raise info 'char mds2=%', mds2;
       original_squared := mds * mds;
       return original_squared;
   end;
begin
    ret := square(23,'abc');
    raise info '%', ret;
end; $$ language plisql;

---global variable the name as local variable
--test ok
create or replace function test_subproc_func(a in out integer) returns integer AS
$$
declare
  mds integer;
  original integer;
  function square(original in out integer) return integer;
  function square(original in out integer) return integer
  AS
  declare
       original_squared integer;
	   a integer;
  BEGIN
       a := 23;
       original_squared := original * original;
       raise info 'mds=%', mds;
       raise info 'original=%', original;
	   raise info 'local var a = %',a;
	   raise info 'global a = %', test_subproc_func.a;
       original := original_squared + 1;
       --return original_squared;
   end;
begin
    mds := 10;
    original := 21;
    original := square(mds);
    raise info '%', original;
    a := original + 1;
    --return mds;
end; $$ language plisql;
/

--print mds=10 original=10 local var a =23
--global a =21 101 102
select * from test_subproc_func(21);
drop function test_subproc_func(integer);

--function the name as global variable
--test failed
do $$
declare
  mds integer;
  function mds(a integer) return integer;
  function mds(a integer) return integer AS
  declare
	mdss integer;
  begin
       mdss := a;
       return mdss;
   end;
begin
    mds := 100;
    mds := mds(mds);
end; $$ language plisql;


--test subproc function out variable ok
--print var = (1,101)  var2=(2,102)
do $$
declare
  salary integer;
  var2 record;
  id integer;
  function test_out(id in out integer, salary out integer) return record
  IS
  declare
       var1 record;
       function test_out(id in out integer,salary out integer) return record
       IS
       declare
            var2 integer;
	   begin
	     salary := 101;
	     var2 := id + 2;
	     id := 1;
	     --return var2;
	end;
   begin
     var1 := test_out(id, salary);
	 raise info 'var=%', var1;
	 salary := 102;
	 id := 2;
	 --return var1;
   end;
begin
    var2 := test_out(id, salary);
    raise info 'var2 = %', var2;
end; $$ language plisql;

--ok
--this because out parameter we have don't handle
-- so it doesn't like oracle
-- test out name=must be assign to null
-- test_out.test_out name=must be assign to null
-- name1= must be assign to null
-- declare name=must be assign to null
do $$
declare
  name varchar(256);
  id integer;
  procedure test_out(id integer, name out varchar)
  IS
  declare
      name1 varchar(256);
      procedure test_out(id integer,name out varchar)
      IS
      declare
         var1 integer;
      begin
         raise info 'test_out.test_out name=%', name;
	     name := 'a test_out.test_out';
      end;
   begin
        raise info 'test out name=%', name;
        name1 := 'must be assign to null';
	test_out(id, name1);
	raise info 'name1=%', name1;
	name := 'return to declare';
   end;
begin
    name := 'must be assign to null';
    id := 1;
    test_out(id, name);
    raise info 'declare name=%', name;
 end; $$ language plisql;


---schema function and subproc function as the same name
create or replace function test_subproc(id integer) returns integer
AS $$
declare
   var1 integer;
begin
    var1 := id;
    raise info 'schema function test_subproc';
    return var1;
END $$ language plisql;
/

--print subproc function test_subproc
do $$
declare
 var1 integer;
 function test_subproc(id integer) return integer
 IS
 declare
    var1 integer;
 begin
     var1 := id;
     raise info 'subproc function test_subproc';
     return var1;
  end;
begin
   var1 := test_subproc(23);
end; $$ language plisql;

--print schema function test_subproc
do $$
declare
  var1 integer;
begin
   var1 := test_subproc(23);
end; $$ language plisql;

--failed wrong number
do $$
declare
 var1 integer;
 function test_subproc(id integer,name varchar) return integer
 IS
 declare
    var1 integer;
 begin
     var1 := 23;
     raise info 'subproc function test_subproc';
     return var1;
  end;
begin
   var1 := test_subproc(23);
end; $$ language plisql;

drop function test_subproc(integer);


---subproc function return object_type
create type test_subproc_type as (id integer,name varchar(23));

--test ok
--print var1=(23, "a object type")
do $$
declare
    var1 test_subproc_type;
    function test_subproc(id integer) return test_subproc_type
    IS
    declare
        var1 test_subproc_type;
    begin
         var1.id := 23;
	 var1.name := 'a object type';
	 return var1;
    end;
begin
    var1 := test_subproc(23);
    raise info 'var1=%', var1;
end;$$ language plisql;

--print id = (1, "welcome to beiing")
--print var1=(23, "a object type")
do $$
declare
    var1 test_subproc_type;
    function test_subproc(id test_subproc_type) return test_subproc_type
    IS
    declare
        var1 test_subproc_type;
    begin
         var1.id := 23;
	 var1.name := 'a object type';
	 raise info 'id = %',id;
	 return var1;
    end;
BEGIN
    var1.id := 1;
	var1.name := 'welcome to beiing';
    var1 := test_subproc(var1);
    raise info 'var1=%', var1;
end;$$ language plisql;

drop type test_subproc_type;

--test function and procedure properties
--test ok
--print 23
do $$
declare
  id integer;
  function test_subproc(id integer) return integer DETERMINISTIC;
  function test_subproc(id integer) return integer DETERMINISTIC
  IS
  declare
   var1 integer;
  begin
     var1 := id;
     return var1;
  end;
begin
    id := test_subproc(23);
    raise info '%', id;
end; $$ language plisql;

--test ok
--print 23
do $$
declare
  id integer;
  function test_subproc(id integer) return integer DETERMINISTIC;
  function test_subproc(id integer) return integer
  IS
  declare
    var1 integer;
  begin
     var1 := id;
     return var1;
  end;
begin
    id := test_subproc(23);
    raise info '%', id;
end; $$ language plisql;

--test ok
--print 23
do $$
declare
  id integer;
  function test_subproc(id integer) return integer;
  function test_subproc(id integer) return integer DETERMINISTIC
 IS
  declare
  var1 integer;
  begin
     var1 := id;
     return var1;
  end;
begin
    id := test_subproc(23);
    raise info '%', id;
end; $$ language plisql;

--test failed
do $$
declare
  id integer;
  function test_subproc(id integer) return integer result_cache;
  function test_subproc(id integer) return integer result_cache
 IS
 declare
  var1 integer;
  begin
     var1 := id;
     return var1;
  end;
begin
    id := test_subproc(23);
    raise info '%', id;
end; $$ language plisql;

--test ok
create or replace function test_mds(id integer) returns integer AS
$$
declare
ids integer;
  function test_subproc(id integer) return integer result_cache;
  function test_subproc(id integer) return integer result_cache
 IS
  declare
  var1 integer;
  begin
     var1 := id;
     return var1;
  end;
begin
    ids := test_subproc(23);
    raise info '%', id;
    return id;
end; $$ language plisql;
/

--print 23
do $$
declare
 id integer;
begin
  id := test_mds(23);
end; $$ language plisql;

--test failed
create or replace function test_mds(id integer) returns integer AS
$$
declare
ids integer;
  function test_subproc(id integer) return integer result_cache relies_on (mds);
  function test_subproc(id integer) return integer result_cache relies_on (mds)
 IS
  declare
  var1 integer;
  begin
     var1 := id;
     return var1;
  end;
begin
    ids := test_subproc(23);
    raise info '%', id;
    return id;
end; $$ language plisql;
/

--test ok
create or replace function test_mds(id integer) returns integer as
$$
declare
  ids integer;
  function test_subproc(id integer) return integer result_cache;
  function test_subproc(id integer) return integer result_cache relies_on (mds)
 IS
  declare
  var1 integer;
  begin
     var1 := id;
     return var1;
  end;
begin
    ids := test_subproc(23);
    raise info '%', id;
    return id;
end; $$ language plisql;

--print 23
do $$
declare
  id integer;
begin
  id := test_mds(23);
end; $$ language plisql;
/

--print 23 23
select * from test_mds(23);

--test ok
create or replace function test_mds(id integer) returns integer AS
$$
declare
  ids integer;
  function test_subproc(id integer) return integer DETERMINISTIC result_cache;
  function test_subproc(id integer) return integer DETERMINISTIC result_cache
  IS
  declare
    var1 integer;
  begin
     var1 := id;
     return var1;
  end;
begin
    ids := test_subproc(23);
    raise info '%', id;
    return id;
end; $$ language plisql;

--print 23
do $$
declare
 id integer;
begin
  id := test_mds(23);
end;$$ language plisql;
/

--test ok
create or replace function test_mds(id integer) returns integer AS
$$
declare
ids integer;
  function test_subproc(id integer) return integer  result_cache DETERMINISTIC;
  function test_subproc(id integer) return integer  result_cache DETERMINISTIC
 IS
  declare
  var1 integer;
  begin
     var1 := id;
     return var1;
  end;
begin
    ids := test_subproc(23);
    raise info '%', id;
    return id;
end;$$ language plisql;
/

--print 23
do $$
declare
 id integer;
begin
  id := test_mds(23);
end;$$ language plisql;

--test ok
create or replace function test_mds(id integer) returns integer AS
$$
declare
  ids integer;
  function test_subproc(id integer) return integer  result_cache;
  function test_subproc(id integer) return integer  result_cache DETERMINISTIC
 IS
  declare
  var1 integer;
  begin
     var1 := id;
     return var1;
  end;
begin
    ids := test_subproc(23);
    raise info '%', id;
    return id;
end; $$ language plisql;
/

--print 23
do $$
declare
 id integer;
begin
  id := test_mds(23);
end; $$ language plisql;

--test ok
create or replace function test_mds(id integer) returns integer AS
$$
declare
  ids integer;
  function test_subproc(id integer) return integer;
  function test_subproc(id integer) return integer DETERMINISTIC
 IS
 declare
  var1 integer;
  begin
     var1 := id;
     return var1;
  end;
begin
    ids := test_subproc(23);
    raise info '%', id;
    return id;
end;$$ language plisql;
/

--print 23
do $$
declare
  id integer;
begin
  id := test_mds(23);
end;$$ language plisql;

--test ok
create or replace function test_mds(id integer) returns integer AS
$$
declare
ids integer;
  function test_subproc(id integer) return integer DETERMINISTIC;
  function test_subproc(id integer) return integer
 IS
 declare
  var1 integer;
  begin
     var1 := id;
     return var1;
  end;
begin
    ids := test_subproc(23);
    raise info '%', id;
    return id;
end; $$ language plisql;
/

--print 23
do $$
declare
  id integer;
begin
  id := test_mds(23);
end; $$ language plisql;

--test failed
create or replace function test_mds(id integer) returns integer AS
$$
declare
ids integer;
  function test_subproc(id integer) return integer RESULT_CACHE;
  function test_subproc(id integer) return integer
 IS
 declare
  var1 integer;
  begin
     var1 := id;
     return var1;
  end;
begin
    ids := test_subproc(23);
    raise info '%', id;
    return id;
end; $$ language plisql;
/

--test failed
create or replace function test_mds(id integer) returns integer AS
$$
declare
ids integer;
  function test_subproc(id integer) return integer;
  function test_subproc(id integer) return integer RESULT_CACHE
 IS
  declare
   var1 integer;
  begin
     var1 := id;
     return var1;
  end;
begin
    ids := test_subproc(23);
    raise info '%', id;
    return id;
end;$$ language plisql;
/

--test failed
create or replace function test_mds(id integer) returns integer AS
$$
declare
ids integer;
  function test_subproc(id integer) return integer;
  function test_subproc(id integer) return integer RESULT_CACHE DETERMINISTIC
 IS
  declare
  var1 integer;
  begin
     var1 := id;
     return var1;
  end;
begin
    ids := test_subproc(23);
    raise info '%', id;
    return id;
end;$$ language plisql;
/

--test failed
create or replace function test_mds(id integer) returns integer AS
$$
declare
ids integer;
  function test_subproc(id integer) return integer RESULT_CACHE DETERMINISTIC;
  function test_subproc(id integer) return integer
 IS
 declare
  var1 integer;
  begin
     var1 := id;
     return var1;
  end;
begin
    ids := test_subproc(23);
    raise info '%', id;
    return id;
end; $$ language plisql;
/

--test failed
create or replace function test_mds(id integer) returns integer AS
$$
declare
ids integer;
  function test_subproc(id integer) return integer RESULT_CACHE;
  function test_subproc(id integer) return integer DETERMINISTIC
 IS
 declare
  var1 integer;
  begin
     var1 := id;
     return var1;
  end;
begin
    ids := test_subproc(23);
    raise info '%', id;
    return id;
end; $$ language plisql;
/

--test failed
create or replace function test_mds(id integer) returns integer AS
$$
declare
ids integer;
  function test_subproc(id integer) return integer DETERMINISTIC;
  function test_subproc(id integer) return integer RESULT_CACHE
 IS
 declare
  var1 integer;
  begin
     var1 := id;
     return var1;
  end;
begin
    ids := test_subproc(23);
    raise info '%', id;
    return id;
end; $$ language plisql;
/

--test failed
do $$
declare
ids integer;
  function test_subproc(id integer) return integer;
  function test_subproc(id integer) return integer  DETERMINISTIC DETERMINISTIC
 IS
 declare
  var1 integer;
  begin
     var1 := id;
     return var1;
  end;
begin
    ids := test_subproc(23);
    raise info '%', id;
    return id;
end; $$ language plisql;

--test failed
create or replace function test_mds(id integer) returns integer AS
$$
declare
  ids integer;
  function test_subproc(id integer) return integer result_cache result_cache;
  function test_subproc(id integer) return integer  result_cache result_cache
 IS
  declare
  var1 integer;
  begin
     var1 := id;
     return var1;
  end;
begin
    ids := test_subproc(23);
    raise info '%', id;
    return id;
end; $$ language plisql;
/

--test ok
create or replace function test_mds(id integer) returns integer AS
$$
declare
ids integer;
  function test_subproc(id integer) return integer DETERMINISTIC RESULT_CACHE;
  function test_subproc(id integer) return integer RESULT_CACHE
 IS
 declare
  var1 integer;
  begin
     var1 := id;
     return var1;
  end;
begin
    ids := test_subproc(23);
    raise info '%', id;
    return id;
end;$$ language plisql;
/

--print 23
do $$
declare
 id integer;
begin
  id := test_mds(23);
end;$$ language plisql;

--test ok
create or replace function test_mds(id integer) returns integer AS
$$
declare
ids integer;
  function test_subproc(id integer) return integer RESULT_CACHE;
  function test_subproc(id integer) return integer RESULT_CACHE DETERMINISTIC
 IS
 declare
  var1 integer;
  begin
     var1 := id;
     return var1;
  end;
begin
    ids := test_subproc(23);
    raise info '%', id;
    return id;
end;$$ language plisql;
/

--print 23
do $$
declare
 id integer;
begin
  id := test_mds(23);
end; $$ language plisql;

--test ok
create or replace function test_mds(id integer) returns integer AS
$$
declare
ids integer;
  function test_subproc(id integer) return integer RESULT_CACHE;
  function test_subproc(id integer) return integer RESULT_CACHE relies_on (mds,sds) DETERMINISTIC
 IS
 declare
  var1 integer;
  begin
     var1 := id;
     return var1;
  end;
begin
    ids := test_subproc(23);
    raise info '%', id;
    return id;
end;$$ language plisql;
/

--print 23
do $$
declare
 id integer;
begin
  id := test_mds(23);
end;$$ language plisql;

drop function test_mds(integer);

--test ok
create or replace procedure test_mds(id integer) AS
$$
declare
ids integer;
  function test_subproc(id integer) return integer RESULT_CACHE;
  function test_subproc(id integer) return integer RESULT_CACHE DETERMINISTIC
 IS
 declare
  var1 integer;
  begin
     var1 := id;
     return var1;
  end;
begin
    ids := test_subproc(23);
    raise info '%', id;
end; $$ language plisql;
/

--print 23
do $$
declare
  id integer;
begin
  test_mds(23);
end; $$ language plisql;

drop procedure test_mds(integer);


--test ok
--print test_subprocproc test_subprocfunc
do $$
declare
  mds integer;
  function test_subprocfunc(id integer) return integer;
  procedure test_subprocproc(id integer);
  procedure test_subprocproc(id integer) IS
  declare
    var1 integer;
  begin
    raise info  'test_subprocproc';
  end;
  function test_subprocfunc(id integer) return integer IS
  declare
    var1 integer;
   begin
     raise info 'test_subprocfunc';
     return id;
   end;
begin
  test_subprocproc(23);
  mds := test_subprocfunc(23);
end; $$ language plisql;

--test ok
create or replace function test_subprocfunc(id integer) returns integer
as
$$
declare
  mds integer;
  function test_subprocfunc(id integer) return integer;
  procedure test_subprocproc(id integer);
  procedure test_subprocproc(id integer) IS
  declare
    var1 integer;
  begin
    raise info 'test_subprocproc';
  end;
  function test_subprocfunc(id integer) return integer IS
  declare
    var1 integer;
   begin
     raise info 'test_subprocfunc';
     return id;
   end;
begin
  test_subprocproc(23);
  mds := test_subprocfunc(23);
  return mds;
end; $$ language plisql;
/

--print test_subprocproc test_subprocfunc
do $$
declare
  id integer;
begin
  id := test_subprocfunc(23);
end; $$ language plisql;

--test accessible by
--failed
do $$
 DECLARE
    var1 integer;
	PROCEDURE test_f(id integer) accessible BY (FUNCTION test_d test_d,
	test_schema test_d,PACKAGE test_d,test_d,PACKAGE PACKAGE PACKAGE,
	TYPE PACKAGE,PACAGE);
	PROCEDURE test_f(id integer) accessible BY (FUNCTION test_d test_d,
	test_schema test_d,PACKAGE test_d,test_d,PACKAGE PACKAGE PACKAGE,
	TYPE PACKAGE,PACAGE) IS
	BEGIN
       raise info 'id=%', id;
	end;
BEGIN
  var1 := 23;
  test_f(var1);
END; $$ language plisql;

--test ok
create or replace procedure test_subprocproc(id integer)
AS
$$
declare
  mds integer;
  function test_subprocfunc(id integer) return integer;
  procedure test_subprocproc(id integer);
  procedure test_subprocproc(id integer) IS
  declare
    var1 integer;
  begin
    raise info 'test_subprocproc';
  end;
  function test_subprocfunc(id integer) return integer IS
  declare
    var1 integer;
   begin
     raise info 'test_subprocfunc';
     return id;
   end;
begin
  test_subprocproc(23);
  mds := test_subprocfunc(23);
end; $$ language plisql;
/

--print test_subprocproc test_subprocfunc
do $$
declare
  id integer;
begin
  test_subprocproc(23);
end; $$ language plisql;


--test ok
create or replace procedure test_subprocproc(id integer) AS
$$
declare
  var1 integer;
  function square(original integer) return integer;
  function square(original integer) return integer
  AS
  declare
       original_squared integer;
       var1 integer;
       function test(test integer) return integer
       AS
       declare
          var1 integer;
	      var2 integer;
       begin
           var1 := 55;
	   raise info '%',var1;
           var2 := var1 + 10;
	   return var2;
       end;
  begin
       var1 := 45;
       original_squared := original * original;
       raise info '%',var1;
       var1 := test(23);
       return original_squared;
   end;
begin
    var1 := 23;
    var1 := square(100);
    raise info '%', var1;
 end; $$ language plisql;
/

--print 45 55 10000
do $$
begin
   test_subprocproc(23);
end; $$ language plisql;

drop procedure test_subprocproc(integer);
drop function test_subprocfunc(integer);

create table mds(id integer,name varchar(23));
insert into mds values(1,'a insert value');

--test global variable assign out
--print before function
-- id=23,id1=14
-- name=we are,name1=global
-- row_var=NULL,row_var1=NULL
-- after function
-- id=23 id1=15
-- name=we are,name1=print a change
-- row_var=NULL,row_var1=(24,"print a change")
do $$
declare
	id integer := 23;
	id1 integer;
	tmp_var mds%rowtype;
	name varchar(23);
	name1 varchar(23);
	row_var mds%rowtype;
	row_var1 mds%rowtype;
	ret integer;
	function change_global(id integer) return integer IS
    declare
		var1 integer;
	begin
	   id1 := 15;
	   tmp_var.id := 0;
	   tmp_var.name := 'subproc array[0]';
	   tmp_var.id := 1;
	   tmp_var.name := 'subproc array[1]';
	   tmp_var.id := 2;
	   tmp_var.name := 'subproc array[2]';
	   tmp_var.id := 3;
	   tmp_var.name := 'subproc array[3]';
	   name1 := 'print a change';
	   row_var1.id := 24;
	   row_var1.name := 'print a change';
	   var1 := 16;
	   return var1;
end;
begin
   id1 := 14;
   tmp_var.id := 0;
   tmp_var.name := 'array[0]';
   tmp_var.id := 1;
   tmp_var.name := 'array[1]';
   tmp_var.id := 2;
   tmp_var.name := 'array[2]';
   tmp_var.id := 3;
   tmp_var.name := 'array[3]';
   name := 'we are';
   name1 := 'global';
   row_var := row_var1;
   raise info 'before function';
   raise info 'id=%,id1=%',id,id1;
   raise info 'name=%,name1=%', name,name1;
   raise info 'row_var=%,row_var1=%', row_var,row_var1;
   ret := change_global(23);
   raise info 'after function';
   raise info 'id=%,id1=%',id,id1;
   raise info 'name=%,name1=%', name,name1;
   raise info 'row_var=%,row_var1=%', row_var,row_var1;
end; $$ language plisql;

drop table mds;

---check call function only by function name
--print function no par
--ret=100
-- procedure no par
do $$
declare
  ret integer;
  function square return integer;
  procedure test_nopar;
  function square return integer
  AS
  declare
       original_squared integer;
  begin
       original_squared := 10 * 10;
       raise info 'function no par';
       return original_squared;
  end;
  procedure test_nopar
  AS
  declare
      original_squared integer;
  begin
      original_squared := 10 * 10;
      raise info 'procedure no par';
  end;
begin
    ret := SQUARE();
    raise info 'ret=%', ret;
    test_nopar();
end; $$ language plisql;

--check nocopy proper
--test ok out arguments has not handle
--print id=46,name=before function
--ret = (46, "test a nocopy")
do $$
declare
   ret record;
   out_var integer;
   name varchar(256);
   function square(id out nocopy integer, name in out nocopy varchar) return record
   IS
   declare
     var1 integer;
   begin
     var1 := 23;
     id := var1 + 23;
     raise info 'id=%,name=%', id,name;
     name := 'test a nocopy';
     --return var1;
   end;
begin
  name := 'before function';
  ret := square(out_var, name);
  raise info 'ret=%', ret;
end; $$ language plisql;

--test failed
do $$
declare
   ret record;
   out_var integer;
   name varchar(256);
   function square(id nocopy integer, name in out nocopy varchar) return record
   IS
   declare
     var1 integer;
   begin
     var1 := 23;
     id := var1 + 23;
     raise info 'id=%,name=%', id,name;
     name := 'test a nocopy';
     --return var1;
   end;
begin
  name := 'before function';
  ret := square(out_var, name);
  raise info 'ret=%', ret;
end; $$ language plisql;

--test repeate declare
--test failed
do $$
declare
  function mds(id integer) return integer;
  function mds(id integer) return integer;
begin
  NULL;
end; $$ language plisql;

--test failed
do $$
declare
  procedure mds(id integer);
  procedure mds(id integer);
begin
  NULL;
end; $$ language plisql;

--only declare but no define raise error
do $$
DECLARE
  var1 integer;
  function mds(id integer) return integer;
begin
  var1 := 23;
end; $$ language plisql;


--again
do $$
DECLARE
  var1 integer;
  function mds(id integer) return integer;
begin
  var1 := mds(23);
end; $$ language plisql;

--define before declare faield
do $$
declare
   function mds(id integer) return integer IS
   declare
      var1 integer;
   begin
      var1 := id;
      return id;
   end;
   function mds(id integer) return integer;
begin
   NULL;
end; $$ language plisql;

--duplicate define failed
do $$
declare
   function mds(id integer) return integer IS
   declare
      var1 integer;
   begin
      var1 := id;
      return id;
   end;
   function mds(id integer) return integer IS
   declare
      var2 integer;
   begin
      var2 := id;
      return id;
    end;
begin
   NULL;
end; $$ language plisql;

--test failed
create or replace function test(id integer) returns integer
AS
$$
declare
  function mds(id integer) return integer;
begin
  return 23;
end; $$ language plisql;
/


do $$
DECLARE
  -- Declare proc1 (forward declaration):
  PROCEDURE proc1(number1 NUMBER);

  -- Declare and define proc2:
  PROCEDURE proc2(number2 NUMBER) IS
  BEGIN
    proc1(number2);
  END;

  -- Define proc 1:
  PROCEDURE proc1(number1 NUMBER) IS
  BEGIN
    proc2 (number1);
  END;
BEGIN
  NULL;
END; $$ language plisql;

--ok
do $$
DECLARE
	PROCEDURE proc1(number1 out NUMBER);
	PROCEDURE proc3(number1 out NUMBER);

	PROCEDURE proc2(number2 NUMBER) IS
	BEGIN
		proc1(number2);
		raise info '%', number2;
		raise info '%','proc2';
	END;

	PROCEDURE proc4(number2 NUMBER) IS
	BEGIN
		raise info '%','proc4';
		proc3(number2);
		raise info 'proc3 out %', number2;
	END;

	PROCEDURE proc1(number1 out NUMBER) IS
	BEGIN
		raise info '%','proc1';
		number1 := 0;
	END;

	PROCEDURE proc3(number1 out NUMBER) IS
	BEGIN
		raise info '%', 'proc3';
		number1 := 1;
	END;

BEGIN
	proc2(1);
	proc4(2);
END; $$ language plisql;

--
--
-- subproc function support polymorphic type
--
--point raise error others is ok
do $$
DECLARE
   var1 integer;
   var2 number;
   var3 point;
   function f1(x anyelement) return anyelement as
   begin
	return x + 1;
   END;
BEGIN
   var1 := f1(42);
   var2 := f1(4.5);
   raise info 'var1=%,var2=%',var1,var2;
   var3 := f1(point(3,4));
end; $$ language plisql;

--global var
CREATE TABLE mds(id integer,name varchar2(1024));

--ok
do $$
DECLARE
   var1 integer;
   var2 number;
   var3 mds%rowtype;
   function f1(x anyelement) return anyelement as
   BEGIN
    var3.id := var3.id + 1;
	var3.name := var3.name || x;
	return x + 1;
   END;
BEGIN
   var3.id := 1;
   var3.name := 'ok';
   var1 := f1(42);
   var2 := f1(4.5);
   raise info 'var1=%,var2=%',var1,var2;
   raise info '%', var3;
end; $$ language plisql;

--two nested ok
do $$
DECLARE
   var1 integer;
   var2 number;
   var3 mds%rowtype;
   function f1(x anyelement) return anyelement AS
   DECLARE
      var1 integer;
	  var2 number;
      FUNCTION test_f(x anyelement) RETURN  anyelement AS
      BEGIN
          var3.id := var3.id + 1;
		  var3.name := var3.name || x;
		  RETURN x + 1;
	  end;
   BEGIN
    var1 := test_f(24);
	var2 := test_f(5.4);
    var3.id := var3.id + 1;
	var3.name := var3.name || x;
	return x + 1;
   END;
BEGIN
   var3.id := 1;
   var3.name := 'ok';
   var1 := f1(42);
   var2 := f1(4.5);
   raise info 'var1=%,var2=%',var1,var2;
   raise info '%', var3;
end; $$ language plisql;

--ok
do $$
DECLARE
    function f1(x anyelement) return anyarray as
	begin
	  return array[x + 1, x + 2];
	end;
BEGIN
   raise info '%', f1(42);
   raise info '%', f1(4.5);
end; $$ language plisql;

--ok
do $$
declare
	function f1(x anyarray) return anyelement as
	begin
	  return x[1];
	END;
BEGIN
   raise info '%,%', f1(array[2,4]),f1(array[4.5,7.7]);
END; $$ language plisql;

do $$
declare
  function f1(x anyarray) return anyarray as
  begin
     return x;
  end;
BEGIN
  raise info '%,%', f1(array[2,4]),f1(array[4.5, 7.7]);
end; $$ language plisql;


-- fail, can't infer type:
do $$
declare
  function f1(x anyelement) return anyrange as
  begin
    return array[x + 1, x + 2];
  end;
BEGIN
  NULL;
end; $$ language plisql;

--ok
do $$
DECLARE
   function f1(x anyrange) return anyarray as
   begin
       return array[lower(x), upper(x)];
   end;
BEGIN
  raise info '%,%', f1(int4range(42,49)), f1(int8range(430,460));
end; $$ language plisql;

--ok
do $$
declare
   function f1(x anycompatible, y anycompatible) RETURN anycompatiblearray AS
	begin
	  return array[x, y];
	end;
BEGIN
   raise info '%,%', f1(2,4),f1(2,4.5);
end; $$ language plisql;

--failed
do $$
declare
  function f1(x anycompatiblerange, y anycompatible, z anycompatible) return anycompatiblearray as
  begin
      return array[lower(x), upper(x), y, z];
  end;
BEGIN
  raise info '%',f1(int4range(42, 49), 11, 2::smallint);
  raise info '%',f1(int4range(42, 49), 11, 4.5); --failed
end; $$ language plisql;


-- fail, can't infer type:
do $$
declare
   function f1(x anycompatible) return anycompatiblerange as
   begin
     return array[x + 1, x + 2];
   end;
BEGIN
  NULL;
end; $$ language plisql;

do $$
declare
   function f1(x anycompatiblerange, y anycompatiblearray) return anycompatiblerange as
   begin
      return x;
   end;
BEGIN
   raise info '%,%',f1(int4range(42, 49), array[11]), f1(int4range(42, 50), array[11]);
END; $$ language plisql;

do $$
DECLARE
   r record;
   function f1(a anyelement, b anyarray,
                   c anycompatible, d anycompatible,
                   x OUT anyarray, y OUT anycompatiblearray) RETURN record
	as
	begin
	  x := a || b;
	  y := array[c, d];
	end;
begin
	r := f1(11, array[1, 2], 42, 34.5, NULL,NULL);
	raise info 'r=%',r;
	r := f1(11, array[1, 2], point(1,2), point(3,4), NULL,NULL);
	raise info 'r=%',r;
	r := f1(11, '{1,2}', point(1,2), '(3,4)', NULL,NULL);
	raise info 'r=%',r;
	r := f1(11, array[1, 2.2], 42, 34.5, NULL,NULL);  -- fail
	raise info 'r=%',r;
END; $$ language plisql;

--
-- Test handling of OUT parameters, including polymorphic cases.
-- Note that RETURN is optional with OUT params; we try both ways.
--
do $$
DECLARE
   var1 integer;
   function f1(i IN int, j out int) RETURN integer is
   begin
     j := i+1;
     return;
   end;
BEGIN
  raise info '%', f1(42, 23);
  SELECT f1(42,23) INTO var1;
  raise info '%', var1;
end; $$ language plisql;

do $$
declare
  function duplic(i IN anyelement, j out anyelement, k out anyarray) RETURN record is
   begin
	  j := i;
	  k := array[j,j];
	  return;
  end;
BEGIN
  raise info '%,%',duplic(42,45,NULL), duplic('foo'::text,'45',NULL);
END; $$ language plisql;

do $$
declare
    function duplic(i IN anycompatiblerange, j out anycompatible, k out anycompatiblearray) RETURN record as
	begin
		j := lower(i);
		k := array[lower(i),upper(i)];
		return;
	end;
BEGIN
	raise info '%,%',duplic(int4range(42,49), NULL,NULL),duplic(int4range('23', '45'), NULL,NULL);
end; $$ language plisql;


--test extral
--error test_f is is out of scope
do $$
declare
  var1 integer;
  function test_f(id integer,name varchar2) return integer IS
  declare
    var2 integer;
  begin
    var2 := 23;
    return 23;
  end;
begin
  var1 := test_f.id;
  var1 := test_f.var2;
  var1 := test_f(23,'xiexie');
end; $$ language plisql;

--raise error test_f is out of scope
do $$
declare
  var1 integer;
  function test_f(id integer,name varchar2) return integer IS
  declare
    var2 integer;
  begin
    var2 := 23;
    return 23;
  end;
begin
  var1 := test_f.var2;
  var1 := test_f(23,'xiexie');
end; $$ language plisql;

--raise error 'TEST_F' reference is out of scope
do $$
declare
  var1 integer;
  function test_f(id integer,name varchar2) return integer IS
  declare
    var2 integer;
  begin
    var2 := 23;
    return 23;
  end;
  function test_f1(id integer,name varchar2) return integer IS
  declare
    var3 integer;
  begin
     var3 := test_f.var2;
     return 24;
   end;
begin
  var1 := test_f1(23,'xiexie');
end; $$ language plisql;

--ok
do $$
declare
  var1 integer;
  function test_f(id integer) return integer IS
  declare
    var3 integer;
  begin
    var1 := test_f.id;
    var3 := test_f.id + 1;
    return var3;
  end;
begin
  var1 := test_f(23);
  raise info '%',var1;
end; $$ language plisql;

--error
do $$
DECLARE
  x  NUMBER := 5;
  function test_f(id integer) return integer;
  function test_f(id integer) return integer;
  function test_f(id integer) return integer is
  begin
    return 1;
  end;
BEGIN
  x := 24;
END; $$ language plisql;

--ok
do $$
DECLARE
  x  NUMBER := 5;
  function test_f(id integer) return integer;
  function test_f(id integer) return integer is
  begin
    return 1;
  end;
BEGIN
  x := 24;
END; $$ language plisql;


---raise info var1=23 var1=24
do $$
declare
  var1 integer := 1;
  function test_f(id integer) return integer IS
  declare
    var2 integer;
    function test_f1(id integer) return integer is
    begin
      raise info 'var1=%',var1;
      var1 := 24;
      return id;
    end;
  begin
    var1 := 23;
    var2 := test_f1(23);
    raise info 'var1 = %', var1;
    return var2;
  end;
begin
  var1 := test_f(23);
end; $$ language plisql;


--oracle raise error,but we success
do $$
declare
  var1 integer;
  function test_f(id integer,name varchar2) return integer is
  begin
    return id;
  end;
  var2 integer;
begin
  var2 := test_f(var1,'ok');
end; $$ language plisql;


--ok
do $$
declare
  function test_f(id integer) return integer;
  var1 integer;
  function test_f(id integer) return integer is
  begin
    var1 := 23;
    return var1;
  end;
begin
  var1 := test_f(23);
end; $$ language plisql;


--oracle raiser error,but we sucess
create or replace function test_f(id integer) returns integer as
$$
declare
  function test_f(id integer) return integer is
  begin
    return 23;
  end;
  var1 integer;
begin
  var1 := 23;
  return 23;
end; $$ language plisql;
/

--ok
SELECT test_f(23) FROM dual;

--drop function
DROP FUNCTION test_f(integer);

--var1 = 23:23
do $$
declare
  var1 integer;
  function test_f(id integer) return integer is
  begin
    id := 23;
	var1 := id;
    return id;
  end;
begin
   var1 := 1;
   raise info 'var1 = %:%', test_f(var1),var1;
end; $$ language plisql;

--raise error
do $$
declare
  var1 integer;
  var2 integer;
  function test_f(id out integer default 23) return integer is
  begin
    raise info 'id = %',id;
    id := 25;
    return id;
  end;
begin
   var2 := test_f(var1);
end; $$ language plisql;

--raise error
do $$
declare
  var1 integer;
  var2 integer;
  function test_f(id in out integer default 23) return integer is
  begin
    raise info 'id = %',id;
    id := 25;
    return id;
  end;
begin
   var2 := test_f(var1);
end; $$ language plisql;

--ok
do $$
declare
  var1 integer;
  var2 integer;
  function test_f(id in integer default 23) return integer is
  begin
    raise info 'id = %',id;
    return id;
  end;
begin
   var2 := test_f(var1);
end; $$ language plisql;

--error
do $$
declare
  var1 integer;
  var2 integer;
  function test_f(id in integer default 23, id2 in out integer default 25) return integer is
  begin
    dbms_output.put_line('id = ' || id);
    return id;
  end;
begin
   var2 := test_f(var1);
end; $$ language plisql;

----ok default value can be discontinuous
do $$
declare
  var1 integer;
  function test_f(id integer default 2,id1 integer,id2 integer default 23) return integer
  is
  begin
     return id + id1 + id2;
  end;
begin
  var1 := test_f(23,25,26);
end; $$ language plisql;

--ok
do $$
declare
  var1 integer;
  function test_f(id integer default 2,id1 integer,id2 integer default 23) return integer
  is
  begin
     return id + id1 + id2;
  end;
begin
  var1 := test_f(id1=>2);
  raise info 'var1=%', var1;
end; $$ language plisql;


--ok
do $$
declare
  var1 integer;
  var2 integer;
  function test_f(id integer default 23,id2 out integer) return integer is
  begin
    id2 := id;
    --return id;
  end;
begin
  var1 := test_f(23,var2);
  raise info 'var1=%', var1;
end; $$ language plisql;

--ok
do $$
declare
  var1 integer;
  function test_f(id out nocopy integer) return integer is
  begin
   id := 23;
  end;
begin
  var1 := test_f(var1);
end; $$ language plisql;

--error
do $$
declare
  var1 integer;
  function test_f(id in nocopy integer) return integer is
  begin
   return 23;
  end;
begin
  var1 := test_f(var1);
end; $$ language plisql;

--ok
do $$
declare
  var1 integer;
  function test_f(id in out nocopy integer) return integer is
  begin
   id := 23;
  end;
begin
  var1 := test_f(var1);
end; $$ language plisql;

--error
do $$
declare
  var1 integer;
  function test_f(id in nocopy integer) return integer is
  begin
   return 23;
  end;
begin
  var1 := test_f(var1);
end; $$ language plisql;

--ok
do $$
declare
  var1 integer;
  function test_f return integer is
  begin
    return 23;
  end;
begin
  var1 := test_f();
end;$$ language plisql;

--dynamic include subproc function ok var1=25
do $$
declare
  var1 integer;
  function test_f(id integer) return integer IS
  declare
    var2 integer;
  begin
    execute  'do $a$ declare
        var1 integer;
		function test_f(id integer) return integer is
		begin
		  return 24;
		end;
       begin
          var1 := test_f(23);
	end; $a$ language plisql';
      return 25;
   end;
begin
   var1 := test_f(23);
   raise info 'var1 = %', var1;
end; $$ language plisql;

--ok
do $$
declare
  var1 integer;
  function test_f(id integer) return integer IS
  declare
    var2 integer;
  begin
    execute  'do $a$ declare
        var1 integer;
	function test_f(id integer) return integer is
	begin
	  return 24;
	end;
       begin
          var1 := test_f(23);
	end; $a$ language plisql;';
      return 25;
   end;
begin
   var1 := test_f(23);
   raise info 'var1 = %', var1;
end; $$ language plisql;

--ok
do $$
declare
  var1 integer;
  function test_f(id integer) return integer IS
  declare
    var2 integer;
  begin
    execute  'do $a$ declare
        var1 integer;
	function test_f1(id integer) return integer is
	begin
	  return 24;
	end;
       begin
          var1 := test_f1(23);
	end; $a$ language plisql';
      return 25;
   end;
begin
   var1 := test_f(23);
   raise info 'var1 = %',var1;
end; $$ language plisql;

--ok
do $$
declare
  var1 integer;
  function test_f(id integer) return integer IS
  declare
    var1 integer;
  begin
    raise info 'function test_f';
    return var1;
  end;
  procedure test_f(id integer) is
  begin
     raise info 'procedure test_f';
  end;
begin
  var1 := test_f(23);
  test_f(23);
end; $$ language plisql;

--ok
do $$
declare
  var1 integer;
  procedure test_f is
  begin
    raise info 'invoke test_f';
  end;
begin
  test_f();
end; $$ language plisql;


--test pipelined failed
do $$
declare
  var1 integer;
  function test_f(id integer) return integer pipelined pipelined is
  begin
    return 23;
  end;
begin
  var1 := test_f(23);
end; $$ language plisql;

--failed
do $$
declare
  var1 integer;
  function test_f(id integer) return integer pipelined pipelined;
  function test_f(id integer) return integer pipelined pipelined is
  begin
    return 23;
  end;
begin
  var1 := test_f(23);
end; $$ language plisql;

--test access by
--failed
do $$
declare
  var1 integer;
  procedure test_f(id integer) accessible by ( package test_pkg,function test_func);
  procedure test_f(id integer) is
  begin
    raise info '%',id;
  end;
begin
  test_f(var1);
end; $$ language plisql;

--test invoker_rights_clause failed
do $$
declare
  var1 integer;
  procedure test_p(id integer) authid definer;
  procedure test_p(id integer) authid define is
  begin
    raise info '%', id;
  end;
begin
  test_p(var1);
end; $$ language plisql;

--oracle failed, but we sucess
do $$
declare
  var1 integer;
  function test_f(id integer) return integer;
  var2 integer;
  procedure test_p(id integer) is
  begin
    raise info 'id = %',id;
    var2 := test_f(23);
  end;
  var3 integer;
  function test_f(id integer) return integer is
  begin
    raise info 'welcome to beijing:%', var3;
    return id;
  end;
begin
  var3 := 25;
  test_p(24);
end; $$ language plisql;


--system func/proc vs subproc func/proc
--ok
create or replace function test_proc1(id integer) returns integer as
$$
declare
  var1 integer;
begin
  var1 := 23;
  return var1;
end; $$ language plisql;
/

--raise error
do $$
declare
  var1 integer;
  procedure test_proc1(id integer) IS
  declare
    var1 integer;
  begin
    raise info 'xiexie';
  end;
begin
  var1 := test_proc1(23);
end; $$ language plisql;

--surcess
do $$
declare
  var1 integer;
begin
  var1 := test_proc1(23);
end; $$ language plisql;

DROP function test_proc1(integer);

--ok
create or replace procedure test_func1(id integer) as
$$
declare
  var1 integer;
begin
  raise info 'id = %', id;
end; $$ language plisql;
/

--error
do $$
declare
  var1 integer;
  function test_func1(id integer) return integer is
  begin
    return 23;
  end;
begin
   test_func1(var1);
end; $$ language plisql;

--sucess
do $$
declare
  var1 integer;
begin
   test_func1(var1);
end; $$ language plisql;

--raise error function keyword not as datum name
do $$
declare
	function integer;
begin
	function := 1;
end; $$ language plisql;

--raise error
do $$
declare
	procedure integer;
begin
	procedure := 1;
end; $$ language plisql;

--ok
do $$
DECLARE
	package integer;
BEGIN
	package := 1;
end; $$ language plisql;

--ok
do $$
declare
	trigger integer;
BEGIN
	trigger := 1;
end; $$ language plisql;

--oracle failed,but we sucess
do $$
DECLARE
	type integer;
begin
	type := 1;
end; $$ language plisql;

---
--ok and print two test_f
do $$
declare
  var1 integer;
  function test_f(id integer) return integer DETERMINISTIC is
  begin
    raise info 'test_f';
    return id;
  end;
begin
  var1 := test_f(23) + test_f(23);
end; $$ language plisql;

--oracle failed,but we success
do $$
declare
  var1 integer;
  var2 integer;
  function test_f(id integer) return integer DETERMINISTIC is
  begin
    raise info 'test_f';
    return id;
  end;
begin
  select test_f(23),test_f(23) into var1,var2 from dual;
end; $$ language plisql;

--raise error
do $$
declare
  name varchar(23);
  id integer;
  function test(name integer) return integer
  as
  begin
       raise info '%',name;
       return 23;
   end;
  function test(name integer) return varchar as
  begin
     raise info '%',name;
	 return 'beijing';
  end;
begin
     name := test(23);
     id := test(23);
end; $$ language plisql;

--ok
do $$
declare
  name varchar(23);
  id integer;
  function test(name integer) return integer
  as
  begin
       raise info '%',name;
       return 23;
   end;
  function test(name integer) return varchar as
  begin
     raise info '%',name;
	 return 'beijing';
  end;
begin
     raise info 'xiexie';
end; $$ language plisql;

--ok
do $$
declare
  name varchar(23);
  id integer;
  function test(name integer) return integer;
  function test(name integer) return varchar;
  function test(name integer) return integer
  as
  begin
       raise info '%',name;
       return 23;
   end;
  function test(name integer) return varchar as
  begin
     raise info '%',name;
	 return 'beijing';
  end;
begin
     raise info 'xiexie';
end; $$ language plisql;

--error
do $$
declare
  name varchar(23);
  id integer;
  function test(name integer) return integer;
  function test(name integer) return integer;
  function test(name integer) return integer
  as
  begin
       raise info '%',name;
       return 23;
   end;
  function test(name integer) return integer as
  begin
     raise info '%',name;
	 return '23';
  end;
begin
     raise info 'xiexie';
end; $$ language plisql;


--test in trigger
create table test_trig_subproc(id integer,name varchar2(256));

--statement trigger
CREATE OR REPLACE FUNCTION after_insert_trig() returns TRIGGER AS $$
declare
   var1 integer;
   function test_f(id integer) return integer is
   begin
      raise info 'var1 :%',var1;
      return id + var1;
    end;
begin
   var1 := 45;
   raise info '%', test_f(23);
   RETURN NULL;
end; $$ language plisql;
/

--ok
create or replace trigger after_insert_trig1 after insert on test_trig_subproc
EXECUTE PROCEDURE after_insert_trig();

--raise info var1:45 and 68
insert into test_trig_subproc values(1,'xiexie');

drop trigger after_insert_trig1 ON test_trig_subproc;
DROP FUNCTION after_insert_trig();

---dml trigger
CREATE OR REPLACE FUNCTION after_insert_trig() returns TRIGGER AS $$
declare
   var1 integer;
   function test_f(id integer) return integer is
   begin
      raise info 'new name :%',new.name;
      return id + new.id;
    end;
begin
   var1 := 45;
   raise info 'old name :%',old.name;
   raise info '%', test_f(23);
   RETURN new;
end; $$ language plisql;
/

create or replace trigger after_insert_trig1 after insert on test_trig_subproc
for each row EXECUTE PROCEDURE after_insert_trig();

--info old name : new name : xiexie 24
insert into test_trig_subproc values(1,'xiexie');

drop trigger after_insert_trig1 ON test_trig_subproc;
DROP FUNCTION after_insert_trig();
drop table test_trig_subproc;

---event trigger
create function test_event_trigger() returns event_trigger as $$
DECLARE
   var1 integer;
   function test_f(id integer) return integer is
    begin
      --global var
      raise info 'test_event_trigger: % %', tg_event, tg_tag;
      return var1 + id;
    end;
BEGIN
    RAISE NOTICE 'test_event_trigger: % %', tg_event, tg_tag;
	var1 := 24;
    var1 := test_f(var1);
END
$$ language plisql;
/

create event trigger regress_event_trigger on ddl_command_start
   execute procedure test_event_trigger();

create table test_subproc_system(id integer);

DROP event TRIGGER regress_event_trigger;
DROP FUNCTION test_event_trigger();
drop table test_subproc_system;

--requite documents example
--ok and print test_subprocproc and test_linefunc
do $$
declare
  mds integer;
  function test_subprocfunc(id integer) return integer;
  procedure test_subprocproc(id integer);
  procedure test_subprocproc(id integer) IS
  declare
    var1 integer;
  begin
    raise info 'test_subprocproc';
  end;
  function test_subprocfunc(id integer) return integer IS
  declare
    var1 integer;
   begin
     raise info 'test_subprocfunc';
     return id;
   end;
begin
  test_subprocproc(23);
  mds := test_subprocfunc(23);
end; $$ language plisql;

--ok
create or replace function test_subprocfunc(id integer) returns integer
as
$$
declare
  mds integer;
  function test_subprocfunc(id integer) return integer;
  procedure test_subprocproc(id integer);
  procedure test_subprocproc(id integer) IS
  declare
    var1 integer;
  begin
    raise info 'test_subprocproc';
  end;
  function test_subprocfunc(id integer) return integer IS
  declare
    var1 integer;
   begin
     raise info 'test_subprocfunc';
     return id;
   end;
begin
  test_subprocproc(23);
  mds := test_subprocfunc(23);
  return mds;
end; $$ language plisql;
/

--ok
do $$
declare
 id integer;
begin
 id := test_subprocfunc(23);
end; $$ language plisql;

--ok
create or replace procedure test_subprocproc(id integer)
AS $$
declare
  mds integer;
  function test_subprocfunc(id integer) return integer;
  procedure test_subprocproc(id integer);
  procedure test_subprocproc(id integer) IS
  declare
    var1 integer;
  begin
     raise info 'test_subprocproc';
  end;
  function test_subprocfunc(id integer) return integer IS
  declare
    var1 integer;
   begin
     raise info 'test_subprocfunc';
     return id;
   end;
begin
  test_subprocproc(23);
  mds := test_subprocfunc(23);
end; $$ language plisql;
/

--ok
do $$
declare
  id integer;
begin
   test_subprocproc(23);
end;$$ language plisql;

DROP PROCEDURE test_subprocproc(integer);
DROP FUNCTION test_subprocfunc(integer);

--print 45 55 10000
do $$
declare
  var1 integer;
  function square(original number) return number;
  function square(original number) return number
  AS
  declare
       original_squared number;
       var1 integer;
       function test(test number) return number
       AS
       declare
          var1 integer;
		  var2 number;
       begin
           var1 := 55;
	       raise info '%',var1;
           var2 := var1 + 10;
	       return var2;
       end;
  begin
       var1 := 45;
       original_squared := original * original;
       raise info '%', var1;
       var1 := test(23);
       return original_squared;
   end;
begin
    var1 := 23;
    raise info '%', square(100);
end; $$ language plisql;

create or replace procedure test_subprocproc(id integer) AS
$$
declare
  var1 integer;
  function square(original integer) return integer;
  function square(original integer) return integer
  AS
  declare
       original_squared integer;
       var1 integer;
       function test(test integer) return integer
       AS
       declare
          var1 integer;
	  var2 integer;
       begin
           var1 := 55;
	   raise info '%', var1;
           var2 := var1 + 10;
	   return var2;
       end;
  begin
       var1 := 45;
       original_squared := original * original;
       raise info '%', var1;
       var1 := test(23);
       return original_squared;
   end;
begin
    var1 := 23;
    var1 := square(100);
    raise info '%', var1;
end; $$ language plisql;
/

--print 45 55 10000
do $$
begin
  test_subprocproc(23);
end; $$ language plisql;

DROP PROCEDURE test_subprocproc(integer);

create or replace function test_nested_f(id integer) returns integer AS
$$
declare
  var1 integer;
  function test_f(id integer) return integer is
  begin
    raise info 'inner test_f';
    return 1;
  end;
begin
  var1 := test_f(23);
  return var1;
end; $$ language plisql;
/

--ok
select test_nested_f(23) from dual;

--failed
select test_f(23) from dual;

DROP function test_nested_f(id integer);

CREATE TABLE r1(id integer,name varchar2(23));

--print var1.id=2 var1.name=welcome
do $$
declare
  var1 r1%rowtype;
  var3 integer;
  function test_f(id integer) return integer IS
  declare
    var2 r1;
  begin
    var2.id := 1;
    var2.name := 'welcome';
    var1.id := var2.id;
    var1.name := var2.name;
    return 1;
  end;
begin
  var3 := test_f(23);
  var1.id := var1.id + 1;
  raise info 'var1.id= % var1.name = %', var1.id, var1.name;
end; $$ language plisql;

--print var1=23 var1 = 24
do $$
declare
  var1 integer := 1;
  function test_f(id integer) return integer IS
  declare
    var2 integer;
    function test_f1(id integer) return integer is
    begin
      raise info 'var1=%', var1;
      var1 := 24;
      return id;
    end;
  begin
    var1 := 23;
    var2 := test_f1(23);
    raise info 'var1=%', var1;
    return var2;
  end;
begin
  var1 := test_f(23);
end; $$ language plisql;

--ok
do $$
declare
  function test_f(id integer) return integer;
  var1 integer;
  function test_f(id integer) return integer is
  begin
    var1 := 23;
    return var1;
  end;
begin
  var1 := test_f(23);
end; $$ language plisql;

--error
do $$
declare
  var1 integer;
  function test_f(id integer,name varchar2) return integer IS
  declare
    var2 integer;
  begin
    var2 := 23;
    return 23;
  end;
begin
  var1 := test_f.id;
  var1 := test_f.var2;
  var1 := test_f(23,'xiexie');
end; $$ language plisql;

--raise error
do $$
declare
  var1 integer;
  function test_f(id integer,name varchar2) return integer IS
  declare
    var2 integer;
  begin
    var2 := 23;
    return 23;
  end;
begin
  var1 := test_f.var2;
  var1 := test_f(23,'xiexie');
end; $$ language plisql;

--raise error
do $$
declare
  var1 integer;
  function test_f(id integer,name varchar2) return integer IS
  declare
    var2 integer;
  begin
    var2 := 23;
    return 23;
  end;
  function test_f1(id integer,name varchar2) return integer IS
  declare
    var3 integer;
  begin
     var3 := test_f.var2;
     return 24;
   end;
begin
  var1 := test_f1(23,'xiexie');
end; $$ language plisql;

--print 23 23
do $$
declare
  name varchar(23);
  id integer;
  function test(id integer,name varchar) return integer
  as
  begin
       raise info '%', id;
       return id;
   end;
  function test(name integer) return varchar AS
  declare
     name2 varchar(256);
  begin
     raise info '%', name;
	 name2 := 'xiexie';
	 return name2;
  end;
begin
     name := test(23);
     id := test(23,name);
 end; $$ language plisql;

--print 23 and xiexie
do $$
declare
  name varchar(23);
  id integer;
  function test(name varchar) return integer
  as
  begin
       raise info '%', name;
       return id;
   end;
  function test(name integer) return integer as
  begin
         raise info '%', name;
	  return id;
  end;
begin
     name := 'xiexie';
     id := test(23);
     id := test(name);
end; $$ language plisql;

--ok print NULL and 23
do $$
declare
  name varchar(23);
  id integer;
  function test(id integer) return integer;
  function test(name integer) return varchar;
  function test(id integer) return integer
  as
  begin
       raise info '%',id;
       return id;
   end;
  function test(name integer) return varchar AS
  declare
     name2 varchar(256);
  begin
     raise info '%',id;
	 name2 := 'xiexie';
	 return name2;
  end;
begin
     name := test(name=>23);
     id := test(id=>23);
end; $$ language plisql;


--raise error
do $$
declare
  name varchar(23);
  id integer;
  function test(id integer) return integer;
  function test(name integer) return varchar;
  function test(id integer) return integer
  as
  begin
       raise info '%',id;
       return id;
   end;
  function test(name integer) return varchar AS
  declare
     name2 varchar(256);
  begin
     raise info '%',id;
	 name2 := 'xiexie';
	 return name2;
  end;
begin
     name := test(23);
     id := test(23);
end; $$ language plisql;

--ok print invoke test_f(integer,varchar2)
-- invoke test_f(varchar2,integer)
do $$
declare
  var1 integer;
  function test_f(id integer,name varchar2) return integer;
  function test_f(name varchar2,id integer) return integer;
  function test_f(name varchar2, id integer) return integer is
  begin
    raise info 'invoke test_f(varchar2,integer)';
    return 23;
  end;
  function test_f(id integer,name varchar2) return integer is
  begin
    raise info 'invoke test_f(integer,varchar2)';
    return 24;
  end;
begin
  var1 := test_f(23,'xiexie');
  var1 := test_f('xiexie', 23);
end; $$ language plisql;

--ok
do $$
declare
   function test_f(id anyelement) return anyelement is
   begin
     return id + 1;
   end;
 begin
    raise info '%', test_f(23);
    raise info '%', test_f(24.1);
 end; $$ language plisql;

--oracle raise error,but we sucess
CREATE TABLE mds(id integer,name varchar2(256));

do $$
DECLARE
  FUNCTION test_f(id integer) RETURN integer;
  FUNCTION test_f1(id integer) RETURN integer IS
  DECLARE
    var1 integer;
  BEGIN
    var1 := test_f(23);
	RETURN var1;
  end;
  var2 mds%rowtype;
  FUNCTION test_f(id integer) RETURN integer IS
  BEGIN
    var2.id := var2.id + 1;
	var2.name := var2.name || 'ok';
	RETURN var2.id;
  end;
 BEGIN
   var2.id := 1;
   var2.name := 'I am ';
   var2.id := test_f1(23);
   raise info '%', var2;
 end; $$ language plisql;

 DROP TABLE mds;

 --test found variable in subproc
create table test_found(id integer,name varchar2(256));

--print out function not found
--subproc not found
do $$
declare
  var1 integer;
  function test_f(id integer) return integer is
  begin
    if found then
      raise info 'subproc found';
    else
      raise info 'subproc not found';
    end if;
    return id;
  end;
begin
   update test_found set id = 2;
   if found then
     raise info 'out function found';
     var1 := test_f(23);
   else
     raise info 'out function not found';
     var1 := test_f(23);
   end if;
end; $$ language plisql;

insert into test_found values(1,'one');

--print out function found
--subproc found
do $$
declare
  var1 integer;
  function test_f(id integer) return integer is
  begin
    if found then
      raise info 'subproc found';
    else
      raise info 'subproc not found';
    end if;
    return id;
  end;
begin
   update test_found set id = 2;
   if found then
     raise info 'out function found';
     var1 := test_f(23);
   else
     raise info 'out function not found';
     var1 := test_f(23);
   end if;
end; $$ language plisql;


--subproc change found variable
--print out function not found
--subproc found
--out function found
do $$
declare
  var1 integer;
  function test_f(id integer) return integer is
  begin
    update test_found set id = 2;
    if found then
      raise info 'subproc found';
    else
      raise info 'subproc not found';
    end if;
    return id;
  end;
begin
   if found then
     raise info 'out function found';
     var1 := test_f(23);
   else
     raise info 'out function not found';
     var1 := test_f(23);
   end if;
   if found then
     raise info 'out function found';
   else
     raise info 'out function not found';
   end if;
 end; $$ language plisql;

--ok
--INFO:  var5=(27,"var3 var1 ")
--INFO:  var1 = (29,"var3 var1  add1 add2"),
--info:  var3 = (28,"var3 var1  add1")

do $$
declare
 var1 test_found%rowtype;
 var2 integer;
 var3 test_found%rowtype;
 FUNCTION test_f(id integer) RETURN integer IS
 DECLARE
    var4 integer;
	var5 test_found%rowtype;
 BEGIN
    var4 := 1;
	var5.id := var4 + id; --27
	var5.name := var3.name || var1.name; --'var3 var1 '
	var3.name := var5.name || ' add1'; --'var3 var1 add1'
	var3.id := var5.id + var1.id; --27 + 1 = 28
	var1.name := var3.name || ' add2'; --'var3 var1 add1 add2'
	var1.id := var3.id + var1.id; --28 + 1 = 29
	raise info 'var5=%', var5; --print var5 = (27, "var3 var1" )
	RETURN var1.id + var3.id;
 end;
BEGIN
  var1.id := 1;
  var1.name := 'var1 ';
  var3.id := 2;
  var3.name := 'var3 ';
  var2 = test_f(26);
  --print var1 = (29,"var3 var1 add1 add2")
  -- var3 = (28,"var3 var1 add1")
  raise info 'var1 = %,var3 = %', var1,var3;
end; $$ language plisql;

DROP TABLE test_found;

--test explain
do $$
DECLARE
  var1 integer;
  var2 text;
  FUNCTION test_f(id integer) RETURN integer IS
  BEGIN
	RETURN 23;
  end;
BEGIN
  SELECT test_f(23) INTO var1 FROM dual;
  raise info '%', var1;
  explain SELECT test_f(23) INTO var2;
  explain SELECT * into var2 FROM test_f(23);
  SELECT * INTO var1 FROM test_f(23);
  raise info '%', var1;
end; $$ language plisql;

--ok print invoke func test_f
-- invoke proc test_f
do $$
declare
  var1 integer;
  procedure test_f(id integer) is
  begin
    raise info 'invoke proc test_f(integer)';
  end;
  PROCEDURE test_f(id integer,name varchar2) IS
  BEGIN
    raise info 'invoke proc test_f(integer,varchar2)';
  end;
  function test_f(id integer) return integer is
  begin
    raise info 'invoke func test_f(integer)';
    return 23;
  end;
  function test_f(id integer, name varchar2) return integer is
  begin
    raise info 'invoke func test_f(integer,varchar2)';
    return 23;
  end;
begin
  var1 := test_f(23);
  test_f(24);
  var1 := test_f(23,'xiexie');
  test_f(24,'xiexie');
end; $$ language plisql;

--test memory
create table rec_typ2(id integer,name varchar2(256));

do $$
declare
  i integer;
  var2 rec_typ2;
  function test_subproc(id integer) return rec_typ2
  is
  begin
      var2.name := 'var2.name';
      var2.id := id;
      var2.id := 25;
      var2.name := 'record include record';
      return var2;
  end;
begin
   for i in 1 .. 10000000 LOOP
      var2 := test_subproc(23);
   end loop;
end; $$ language plisql;

DROP TABLE rec_typ2;
DROP TABLE r1;
