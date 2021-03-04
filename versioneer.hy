(import os [os [path listdir]] subprocess
        [glob [glob]]
        [hashlib [sha1]]
        [humanhash [humanize]]
        [pprint [pprint]]
        json aiosql sqlite3)

(require [hy.extra.anaphoric [*]])

(setv db-ops "db_ops.sql"
      sql-filename "versioneer.sqlite"      
      connect (fn [] (sqlite3.connect sql-filename))
      help-msg "Options:

run <dir> [rem] [exts] -- assumes runner in ./run.sh
rem <hash> <remarks> -- adds output commands
list -- lists hashes
ls <hash>   -- lists files in a hash
get <hash> <filename> -- accesses file")      

(defn setup-db [conn]
 (setv db (aiosql.from-path db-ops "sqlite3"))
 (unless (path.isfile sql-filename) (do (print "aeeee") (db.setup conn)))
 db) 

(setv db (with [conn (connect)] (setup-db conn))) 

(defn codename [fileset]
  (-> (json.dumps fileset) 
      (.encode "utf-8")  
      sha1 .hexdigest humanize)) 

(defn lsfiles [dir ext-list] 
 (flatten  (ap-map (glob (path.join dir it) :recursive True) ext-list))) 

(defn openfileset [dir ext-list] 
 (dfor file (lsfiles dir  ext-list)
         [file (with [f (open file "r")] (f.read))]))
     

(defn run-and-store [conn dir runner &optional [rem ""] [exts ["*.py" "*.hy" "*.sh"]]]
 (setv db (setup-db conn) 
       [human-hash code] ((juxt codename json.dumps) (openfileset dir exts))
       output (subprocess.run [runner] :stdout subprocess.PIPE))

 (db.store-code conn :hash human-hash  :rem rem  :code code) 
 (db.store-output conn :hash human-hash :output (.decode output.stdout "utf-8"))) 

(defn append-comments [db conn human-hash rem]
  (db.append-comments conn :hash human-hash :rem rem))  

(defn ls-entries [db conn]
  (db.list-entries conn)) 

(defn get-code [db conn human-hash]
 (-> (db.get-code conn :hash human-hash) first json.loads))

(defn get-output [db conn human-hash]
  (db.get-output conn :hash human-hash))
 
(defn get-file-list [db conn human-hash]
 (-> (get-code conn human-hash) .keys list)) 

(defn get-file [db conn human-hash filename]
 (get (get-code conn human-hash) filename))

(defmain [self &optional cmd arg1 arg2 arg3 arg4 arg5 arg6 arg7]
 ;(print [arg1 arg2 arg3 arg4 arg5 arg6 arg7])
 (with [conn (connect)]
   (setup-db conn)
   (cond [(= cmd "run")  (run-and-store db conn arg1 "./run.sh" 
                           (if arg2 arg2 "")
                           (if arg3 arg3 ["*.py" "*.hy" "*.sh"]))]                         
         [(= cmd "rem")  (append-comments db conn arg1 arg2)]
         [(= cmd "list") (print (ls-entries conn))]
         [(= cmd "ls")   (print (get-file-list db conn arg1))]
         [(= cmd "get")  (print (get-file db conn arg1 arg2))]
         [True (print help-msg)])))
