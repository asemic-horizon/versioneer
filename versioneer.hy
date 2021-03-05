(require [hy.extra.anaphoric [*]])
(import os [os [path]] subprocess
        [glob [glob]]
        [hashlib [sha1]]
        [humanhash [humanize]]
        [pprint [pprint]]
        json aiosql sqlite3)

;; global variables in lieu of a config file
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
      

(defn setup-db [conn]
 (setv db (aiosql.from-path db-ops "sqlite3"))
 (unless (path.isfile sql-filename) (do (print "Schema setup") (db.setup conn)))
 db) 


(defn codename [fileset]
    (-> (json.dumps fileset) 
        (.encode "utf-8")  
        sha1 .hexdigest (humanize :words 2))) 

(defn openfileset [dir ext-list]
   (setv file-list (flatten (ap-map (glob (path.join dir it)) ext-list))) 
   (dfor file file-list 
         [file (with [f (open file "r")] (f.read))]))
     

(defn run-and-store [db conn dir runner &optional [rem ""] [exts ["*.py" "*.hy" "*.sh"]]]
   (setv [human-hash code] ((juxt codename json.dumps) (openfileset dir exts))

         output (subprocess.check_process [runner]  :stdout subprocess.PIPE  :shell True))

   (db.store-code conn :hash human-hash  :rem rem  :code code) 
   (db.store-output conn :hash human-hash  :output (.decode output.stdout "utf-8")) 
   human-hash)


(defn get-code [db conn human-hash]
   (-> (db.get-code conn :hash human-hash) first json.loads))
 
(defn get-file-list [db conn human-hash]
   (-> (get-code db conn :human-hash human-hash) .keys list)) 

(defn get-file [db conn human-hash filename]
  (get (get-code db conn human-hash) filename))

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
