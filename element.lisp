#|
 This file is a part of cl-gltf
 (c) 2022 Shirakumo http://tymoon.eu (shinmera@tymoon.eu)
 Author: Nicolas Hafner <shinmera@tymoon.eu>
|#

(in-package #:org.shirakumo.fraf.gltf)

(defgeneric initargs (type json gltf)
  (:method-combination append))

(defun removef (plist &rest keys)
  (loop for (key val) on plist by #'cddr
        for found = (find key keys)
        unless found collect key
        unless found collect val))

(defun to-json-name (name)
  (with-output-to-string (out)
    (loop with upcase-next = NIL
          for char across (string name)
          do (cond ((char= #\- char)
                    (setf upcase-next T))
                   (upcase-next
                    (setf upcase-next NIL)
                    (write-char (char-upcase char) out))
                   (T
                    (write-char (char-downcase char) out))))))

(defun normalize-slotdef (slot &rest args &key name ref parse initarg initform accessor reader writer)
  (if (eql name 'null)
      (list* slot (removef args :name))
      (list* slot
             :name (or name (to-json-name slot))
             :ref ref
             :parse parse
             :initarg (or initarg (intern (string slot) "KEYWORD"))
             :initform initform
             (if (or reader writer accessor)
                 (append (when reader `(:reader ,reader))
                         (when writer `(:writer ,writer))
                         (when accessor `(:accessor ,accessor)))
                 `(:accessor ,slot)))))

(defvar *describe-indent* 0)

(defun describe-slot (name value maxlength stream)
  (flet ((write-slot (name)
           (format stream "~va- ~va " (* 2 *describe-indent*) "" maxlength name)))
    (typecase value
      (null)
      ((and array (not string))
       (write-slot name)
       (let ((*describe-indent* (1+ *describe-indent*)))
         (cond ((= 0 (length value))
                (terpri stream))
               ((typep (aref value 0) 'gltf-element)
                (terpri stream)
                (loop for element across value do (describe-object element stream)))
               (T
                (format stream "~a~%" value)))))
      (hash-table
       (write-slot name) (terpri stream)
       (loop for k being the hash-keys of value
             for v being the hash-values of value
             do (let ((*describe-indent* (1+ *describe-indent*)))
                  (describe-slot k v maxlength stream))))
      (gltf-element
       (write-slot name) (terpri stream)
       (let ((*describe-indent* (1+ *describe-indent*)))
         (describe-object value stream)))
      (T
       (write-slot name)
       (format stream "~s~%" value)))))

(defmacro define-element (name superclasses slots &rest options)
  (let* ((slots (loop for slot in slots collect (apply #'normalize-slotdef (if (listp slot) slot (list slot)))))
         (maxlength (loop for slot in slots maximize (length (string (first slot)))))
         (none (gensym "NONE")))
    `(progn
       (defclass ,name ,superclasses
         ,(loop for (slot . args) in slots
                collect (list* slot (removef args :name :ref :parse)))
         ,@options)

       (defmethod initargs append ((type ,name) json gltf)
         (let ((result ()))
           ,@(loop for (slot . args) in slots
                   when (getf args :name)
                   collect `(let ((value (gethash ,(getf args :name) json ',none)))
                              (unless (eq value ',none)
                                (push ,(destructuring-bind (&key ref parse &allow-other-keys) args
                                         (cond (ref
                                                `(resolve value ',ref gltf))
                                               (parse
                                                `(parse-from value ',parse gltf))
                                               (T
                                                `value)))
                                      result)
                                (push ,(getf args :initarg) result))))
           result))

       (defmethod describe-object ((type ,name) stream)
         (format stream "~va~a" (* 2 *describe-indent*) "" (type-of type))
         (if (typep type 'indexed-element)
             (format stream " ~d" (idx type)))
         (terpri stream)
         ,@(loop for (name . args) in slots
                 when (getf args :name)
                 collect `(describe-slot ',name (slot-value type ',name) ,maxlength stream))))))
