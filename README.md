This is a fairly simple script in a fairly obscure language, so it makes sense to go through-it in "literate programming" style. Check the actual `versioneer.hy` file for the most recent script, which may have changed.

```hy 
(require [hy.extra.anaphoric [*]])
```

Hy is Python's freakiest daughter. By both criteria it's a Lisp, hence it has macros. Macros are imported with `require`, 
while ordinary Python imports are imported with `import`. 

```hy
(import os [os [path]] subprocess
        [glob [glob]]
        [hashlib [sha1]]
        [humanhash [humanize]]
        [pprint [pprint]]
        json aiosql sqlite3)
```

`aiosql` is the most interesting import there; it provides for a separation of concerns between SQL code and imperative code by allowing you to define "functions" (in the separate .sql file included in this project) that get transformed into Python methods. But first let us define some global constants, lacking a further separate config file.

```hy
(setv db-ops "db_ops.sql"
      sql-filename "versioneer.sqlite"      
      connect (fn [] (sqlite3.connect sql-filename))
      help-msg "Options:

run <dir> [rem] [exts] -- assumes runner in ./run.sh
rem <hash> <remarks> -- adds output commands
list -- lists hashes
ls <hash>   -- lists files in a hash
read <hash> -- read output in a hash
get <hash> <filename> -- accesses file")
```

Here `aiosql` springs into action: a `db` object is created that allows us to access functions defined in pure SQL in `db_ops.sql`. 

Note that, in Python, opening a sqlite connection for a file that doesn't exist creates it. So unless our database file already exists, we have to set up its table schema with `db.setup` (which is defined in the .sql file!).

Also note that Hy functions return by default the last form mentioned. This means: if a file already exists and we don't execute `db.setup`, then we're already implicitly returning the `db` object; on the other hand, if the file does not exist, then we'd be returning the results of `(db.setup conn)` -- if we failed to just say `db` at the end. 

```hy
(defn setup-db [conn]
 (setv db (aiosql.from-path db-ops "sqlite3"))
 (unless (path.isfile sql-filename) (do (print "Schema setup") (db.setup conn)))
 db) 
```

Here's something that's not so easily achievable in straight Python: 

* `ap-map` is a shorter way of saying `map` -- apply every function to an element of a list. Hy also has list comprehensions, but here this is clearer. 
* Each call to `glob` returns a list. We're left with a list of lists. Something really annoying about Python is that there's no generic and standard way of flattening lists-of-lists-of-lists etc. to a single list. This is on the standard lib of Hy.
* `dfor` is a dict comprehension: what you see below corresponds to `{file: with open(file),"r" as file: f.read() for file in file_list )`. But wait, this is impossible in Python. (Hy provides a `hy2py` tool so you can spy their mavericky solution to run this as Python code.)

As a result, we get a dict that has all files in path `dir` with extensions in `ext-list` with filenames as keys.

```hy
(defn openfileset [dir ext-list]
   (setv file-list (flatten (ap-map (glob (path.join dir it)) ext-list))) 
   (dfor file file-list 
         [file (with [f (open file "r")] (f.read))]))
```  

Like a Lisp, Hy is full of ~~parentheses~~ brackets. But often they can be avoided using the built-in threading macro `->`, which works a bit like Unix pipes: `(-> (json.dumps fileset) (.encode "utf-8") print)` means `(print (.encode (json.dumps fileset) "utf-8"))`. So in the code below, we take the json dump, encode it, take its sha1 hash, take the hexdigest of this hash and humanize it (convert to English words, provided by the `humanhash3` package). As a result, a human-readable digest of a fileset is taken.

```hy
(defn codename [fileset]
    (-> (json.dumps fileset) 
        (.encode "utf-8")  
        sha1 .hexdigest humanize) 
```

This is the heart of our script: we (I) get all the code in the path of interest, dump it into a string but also run it through `codename` (this is what `juxt` does; it saves us an intermediary variable for additional readability) and (II) execute a script called "runner" and capture its output. Then everything is stored on the db, with optional remarks about the code.

```hy
(defn run-and-store [db conn dir runner &optional [rem ""] [exts ["*.py" "*.hy" "*.sh"]]]
   (setv [human-hash code] ((juxt codename json.dumps) (openfileset dir exts))  ; (I)

         output (subprocess.check_process [runner]  :stdout subprocess.PIPE  :shell True)) ; (II)

   (db.store-code conn :hash human-hash  :rem rem  :code code) 
   (db.store-output conn :hash human-hash  :output (.decode output.stdout "utf-8")) 
   human-hash)
```

Most other db operations are actually dèfined in the external .sql file. Just a few need a little more massage on the ~~Pyth~~ Hy side.

This again uses the threading syntax to first get the code from the database using the externally-defined SQL query `get-code`, then use just the first result (that matches the human hash), then parse it as a dictionary.
```hy
(defn get-code [db conn human-hash]
   (-> (db.get-code conn :hash human-hash) first json.loads))
 ```

This now uses the previously-defined function to get the code as a dict, then get its keys, then convert the keys iterator into a list. 

```hy
(defn get-file-list [db conn human-hash]
   (-> (get-code db conn :human-hash human-hash) .keys list)) 
```

The word `get` is used here to get a value from a dict. An alternate syntax, more useful when you have concrete keys is `(. my-dict "key")`; but here this could be confused for a `filename` method of the `(get-code ...)` result. 

```hy
(defn get-file [db conn human-hash filename]
  (get (get-code db conn human-hash) filename))
```

A `defmaìn` block, similarly to `if __main == ...` in Python, transforms what could be used as a module/library (even from within Python) into a CLI script with arguments. You can give arbitrary argument names, but this is equivalent in Python to reading values of `sys.argv`; there is no argparse magic here. Here I called the arguments `arg1, ...` generically because they're used differently depending on what the value of `cmd` is. 

`cond` is just a multi-pronged if/else syntax familiar to anyone who had Scheme in college. 

```hy
(defmain [self &optional cmd arg1 arg2 arg3 arg4 arg5 arg6 arg7]
  (with [conn (connect)]
     (setv db (setup-db conn))
     (cond [(= cmd "run")  (print (run-and-store db conn arg1 "./run.sh" 
                                   (if arg2 arg2 "")
                                   (if arg3 arg3 ["*.py" "*.hy" "*.sh"])))]                         
           [(= cmd "rem")  (db.append-comments conn :hash arg1  :rem arg2)]
           [(= cmd "list") (pprint  (db.list-entries conn))]
           [(= cmd "ls")   (pprint (get-file-list db conn arg1))]
           [(= cmd "get")  (pprint (get-file db conn arg1 arg2))]
           [(= cmd "read") (print (last (db.get-output conn :hash arg1)))]
           [True (print help-msg)])))
```

I have just a further note about functionality. When you run code to store its output, the option to also add output comments is not available. This is because you will probably know what to write only after you inspect the output. 