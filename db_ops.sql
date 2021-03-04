--name: setup!

create table versioneer (
  loc_id integer primary key, 
  time timestamp default current_timestamp, 
  human_hash text,
  description text,
  code_comments text,
  run_comments text, 
  code text, 
  output text); 

--name: store-code!
	insert into versioneer
      (human_hash, code, code_comments)
	  values (:hash, :code, :rem);

--name: store-output!
 update  versioneer 
    set output = :output, time = current_timestamp
    where human_hash = :hash;

--name: append-comments!
  update versioneer
    set run_comments = :rem 
    where human_hash = :hash;

--name: list-entries
  select human_hash, time, code_comments, run_comments
    from versioneer;

--name: get-code^
  select code from versioneer where human_hash = :hash limit 1;


--name: get-output^
    select output from versioneer where human_hash = :hash limit 1;

