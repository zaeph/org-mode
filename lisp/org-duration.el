;;; org-duration.el --- Library handling durations   -*- lexical-binding: t; -*-

;; Copyright (C) 2017  Nicolas Goaziou

;; Author: Nicolas Goaziou <mail@nicolasgoaziou.fr>
;; Keywords: outlines, hypermedia, calendar, wp

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; This library provides tools to manipulate durations.  A duration
;; can have multiple formats:
;;
;;   - 3:12
;;   - 1:23:45
;;   - 1y 3d 3h 4min
;;   - 3d 13:35
;;   - 2.35h
;;
;; More accurately, it consists of numbers and units, as defined in
;; variable `org-duration-units', separated with white spaces, and
;; a "H:MM" or "H:MM:SS" part.  White spaces are tolerated between the
;; number and its relative unit.  Variable `org-duration-format'
;; controls duration default representation.
;;
;; The library provides functions allowing to convert a duration to,
;; and from, a number of minutes: `org-duration-to-minutes' and
;; `org-duration-from-minutes'.  It also provides two lesser tools:
;; `org-duration-p', and `org-duration-h:mm-only-p'.
;;
;; Users can set the number of minutes per unit, or define new units,
;; in `org-duration-units'.  The library also supports canonical
;; duration, i.e., a duration that doesn't depend on user's settings,
;; through optional arguments.

;;; Code:

(require 'cl-lib)
(require 'org-macs)
(declare-function org-trim "org-trim" (s &optional keep-lead))


;;; Public variables

(defconst org-duration-canonical-units
  `(("min" . 1)
    ("h" . 60)
    ("d" . ,(* 60 24)))
  "Canonical time duration units.
See `org-duration-units' for details.")

(defcustom org-duration-units
  `(("min" . 1)
    ("h" . 60)
    ("d" . ,(* 60 24))
    ("w" . ,(* 60 24 7))
    ("m" . ,(* 60 24 30))
    ("y" . ,(* 60 24 365.25)))
  "Conversion factor to minutes for a duration.

Each entry has the form (UNIT . MODIFIER).

In a duration string, a number followed by UNIT is multiplied by
the specified number of MODIFIER to obtain a duration in minutes.

For example, the following value

  \\=`((\"min\" . 1)
    (\"h\" . 60)
    (\"d\" . ,(* 60 8))
    (\"w\" . ,(* 60 8 5))
    (\"m\" . ,(* 60 8 5 4))
    (\"y\" . ,(* 60 8 5 4 10)))

is meaningful if you work an average of 8 hours per day, 5 days
a week, 4 weeks a month and 10 months a year.

When setting this variable outside the Customize interface, make
to call the following command:

  \\[org-duration-set-regexps\\]"
  :group 'org-agenda
  :version "26.1"
  :package-version '(Org . "9.1")
  :set (lambda (var val) (set-default var val) (org-duration-set-regexps))
  :initialize 'custom-initialize-changed
  :type '(choice
	  (const :tag "H:MM" 'h:mm)
	  (const :tag "H:MM:SS" 'h:mm:ss)
	  (alist :key-type (string :tag "Unit")
		 :value-type (number :tag "Modifier"))))

(defcustom org-duration-format '(("d" . nil) (special . h:mm))
  "Format definition for a duration.

The value can be set to, respectively, `h:mm:ss' or `h:mm', which
means a duration is expressed as, respectively, a \"H:MM:SS\" or
\"H:MM\" string.

Alternatively, the value can be a list of entries following the
pattern:

  (UNIT . REQUIRED?)

UNIT is a unit string, as defined in `org-duration-units'.  The
time duration is formatted using only the time components that
are specified here.  If a time unit in missing, it falls back to
the next smallest unit.

A non-nil REQUIRED? value for these keys indicates that the
corresponding time component should always be included, even if
its value is 0.

Eventually, the list can contain an entry indicating special
formatting needs.  It can follow one of the three following
patterns:

  (special . h:mm)
  (special . h:mm:ss)
  (special . PRECISION)

When any of the first two is present, a duration is expressed in
mixed mode, where the hours and minutes of the duration are
expressed as a \"H:MM:SS\" or \"H:MM\" string while still using
other units defined.

With the last pattern, a duration is expressed with a single
unit, PRECISION being the number of decimal places to show.  The
unit chosen is the first one required or with a non-zero integer
part.  If there is no such unit, the smallest one is used.

For example,

   ((\"d\" . nil) (\"h\" . t) (\"min\" . t))

means a duration longer than a day is expressed in days, hours
and minutes, whereas a duration shorter than a day is always
expressed in hours and minutes, even when shorter than an hour.

On the other hand, the value

  ((\"d\" . nil) (\"min\" . nil))

means a duration longer than a day is expressed in days and
minutes, whereas a duration shorter than a day is expressed
entirely in minutes, even when longer than an hour.

The following format

  ((\"d\" . nil) (special . h:mm))

means that any duration longer than a day is expressed with both
a \"d\" unit and a \"H:MM\" part, whereas a duration shorter than
a day is expressed only as a \"H:MM\" string.

Eventually,

  ((\"d\" . nil) (\"h\" . nil) (special . 2))

expresses a duration longer than a day as a decimal number, with
a 2-digits fractional part, of \"d\" unit.  A duration shorter
than a day uses \"h\" unit instead."
  :group 'org-time
  :group 'org-clock
  :version "26.1"
  :package-version '(Org . "9.1")
  :type '(choice
	  (const :tag "Use H:MM" h:mm)
	  (const :tag "Use H:MM:SS" h:mm:ss)
	  (repeat :tag "Use units"
		  (choice
		   (cons :tag "Use units"
			 (string :tag "Unit")
			 (choice (const :tag "Skip when zero" nil)
				 (const :tag "Always used" t)))
		   (cons :tag "Use a single decimal unit"
			 (const special)
			 (integer :tag "Number of decimals"))
		   (cons :tag "Use both units and H:MM"
			 (const special)
			 (const h:mm))
		   (cons :tag "Use both units and H:MM:SS"
			 (const special)
			 (const h:mm:ss))))))


;;; Internal variables and functions

(defvar org-duration--h:mm-re "\\`[0-9]+\\(?::[0-9]\\{2\\}\\)\\{1,2\\}\\'"
  "Regexp matching a duration expressed with H:MM or H:MM:SS format.
See `org-duration--h:mm:ss-re' to only match the latter.  Hours
can use any number of digits.")

(defvar org-duration--h:mm:ss-re "\\`[0-9]+\\(?::[0-9]\\{2\\}\\)\\{2\\}\\'"
  "Regexp matching a duration expressed H:MM:SS format.
See `org-duration--h:mm-re' to also support H:MM format.  Hours
can use any number of digits.")

(defvar org-duration--unit-re nil
  "Regexp matching a duration with an unit.
Allowed units are defined in `org-duration-units'.  Match group
1 contains the bare number.  Match group 2 contains the unit.")

(defvar org-duration--full-re nil
  "Regexp matching a duration expressed with units.
Allowed units are defined in `org-duration-units'.")

(defvar org-duration--mixed-re nil
  "Regexp matching a duration expressed with units and H:MM or H:MM:SS format.
Allowed units are defined in `org-duration-units'.  Match group
1 contains units part.  Match group 2 contains H:MM or H:MM:SS
part.")

(defun org-duration--modifier (unit &optional canonical)
  "Return modifier associated to string UNIT.
When optional argument CANONICAL is non-nil, refer to
`org-duration-canonical-units' instead of `org-duration-units'."
  (or (cdr (assoc unit (if canonical
			   org-duration-canonical-units
			 org-duration-units)))
      (error "Unknown unit: %S" unit)))


;;; Public functions

;;;###autoload
(defun org-duration-set-regexps ()
  "Set duration related regexps."
  (interactive)
  (setq org-duration--unit-re
	(concat "\\([0-9]+\\(?:\\.[0-9]*\\)?\\)[ \t]*"
		;; Since user-defined units in `org-duration-units'
		;; can differ from canonical units in
		;; `org-duration-canonical-units', include both in
		;; regexp.
		(regexp-opt (mapcar #'car (append org-duration-canonical-units
						  org-duration-units))
			    t)))
  (setq org-duration--full-re
	(format "\\`%s\\(?:[ \t]+%s\\)*\\'"
		org-duration--unit-re
		org-duration--unit-re))
  (setq org-duration--mixed-re
	(format "\\`\\(?1:%s\\(?:[ \t]+%s\\)*\\)[ \t]+\
\\(?2:[0-9]+\\(?::[0-9][0-9]\\)\\{1,2\\}\\)\\'"
		org-duration--unit-re
		org-duration--unit-re)))

;;;###autoload
(defun org-duration-p (s)
  "Non-nil when string S is a time duration."
  (and (stringp s)
       (or (string-match-p org-duration--full-re s)
	   (string-match-p org-duration--mixed-re s)
	   (string-match-p org-duration--h:mm-re s))))

;;;###autoload
(defun org-duration-to-minutes (duration &optional canonical)
  "Return number of minutes of DURATION string.

When optional argument CANONICAL is non-nil, ignore
`org-duration-units' and use standard time units value.

As a special case, a bare number represents minutes.

Return value as a float.  Raise an error if duration format is
not recognized."
  (cond
   ((string-match-p org-duration--h:mm-re duration)
    (pcase-let ((`(,hours ,minutes ,seconds)
		 (mapcar #'string-to-number (split-string duration ":"))))
      (+ (/ (or seconds 0) 60.0) minutes (* 60 hours))))
   ((string-match-p org-duration--full-re duration)
    (let ((minutes 0)
	  (s -1))
      (while (setq s (string-match org-duration--unit-re duration (1+ s)))
	(let ((value (string-to-number (match-string 1 duration)))
	      (unit (match-string 2 duration)))
	  (cl-incf minutes (* value (org-duration--modifier unit canonical)))))
      (float minutes)))
   ((string-match org-duration--mixed-re duration)
    (let ((units-part (match-string 1 duration))
	  (hms-part (match-string 2 duration)))
      (+ (org-duration-to-minutes units-part)
	 (org-duration-to-minutes hms-part))))
   ((string-match-p "\\`[0-9]+\\(\\.[0-9]*\\)?\\'" duration)
    (float (string-to-number duration)))
   (t (error "Invalid duration format: %S" duration))))

;;;###autoload
(defun org-duration-from-minutes (minutes &optional fmt canonical)
  "Return duration string for a given number of MINUTES.

Format duration according to `org-duration-format' or FMT, when
non-nil.

When optional argument CANONICAL is non-nil, ignore
`org-duration-units' and use standard time units value.

Raise an error if expected format is unknown."
  (pcase (or fmt org-duration-format)
    (`h:mm
     (let ((minutes (floor minutes)))
       (format "%d:%02d" (/ minutes 60) (mod minutes 60))))
    (`h:mm:ss
     (let ((seconds (floor (* 60 minutes)) ))
       (format "%s:%02d"
	       (org-duration-from-minutes (/ seconds 60) 'h:mm)
	       (mod seconds 60))))
    ((pred atom) (error "Invalid duration format specification: %S" fmt))
    ;; Mixed format.  Call recursively the function on both parts.
    ((and duration-format
	  (let `(special . ,(and mode (or `h:mm:ss `h:mm)))
	    (assq 'special duration-format)))
     (let* ((truncated-format
	     ;; Remove "special" mode from duration format in order to
	     ;; recurse properly.  Also remove units smaller or equal
	     ;; to an hour since H:MM part takes care of it.
	     (cl-remove-if-not
	      (lambda (pair)
		(pcase pair
		  (`(,(and unit (pred stringp)) . ,_)
		   (> (org-duration--modifier unit canonical) 60))
		  (_ nil)))
	      duration-format))
	    (min-modifier		;smallest modifier above hour
	     (and truncated-format
		  (apply #'min
			 (mapcar (lambda (p)
				   (org-duration--modifier (car p) canonical))
				 truncated-format)))))
       (if (or (null min-modifier) (< minutes min-modifier))
	   ;; There is not unit above the hour or the smallest unit
	   ;; above the hour is too large for the number of minutes we
	   ;; need to represent.  Use H:MM or H:MM:SS syntax.
	   (org-duration-from-minutes minutes mode canonical)
	 ;; Represent minutes above hour using provided units and H:MM
	 ;; or H:MM:SS below.
	 (let* ((units-part (* min-modifier (floor (/ minutes min-modifier))))
		(minutes-part (- minutes units-part)))
	   (concat
	    (org-duration-from-minutes units-part truncated-format canonical)
	    " "
	    (org-duration-from-minutes minutes-part mode))))))
    ;; Units format.
    (duration-format
     (let* ((fractional
	     (let ((digits (cdr (assq 'special duration-format))))
	       (and digits
		    (or (wholenump digits)
			(error "Unknown formatting directive: %S" digits))
		    (format "%%.%df" digits))))
	    (selected-units
	     (sort (cl-remove-if
		    ;; Ignore special format cells.
		    (lambda (pair) (pcase pair (`(special . ,_) t) (_ nil)))
		    duration-format)
		   (lambda (a b)
		     (> (org-duration--modifier (car a) canonical)
			(org-duration--modifier (car b) canonical))))))
       (cond
	;; Fractional duration: use first unit that is either required
	;; or smaller than MINUTES.
	(fractional
	 (let* ((unit (car
		       (or (cl-find-if
			    (lambda (pair)
			      (pcase pair
				(`(,u . ,req?)
				 (or req?
				     (<= (org-duration--modifier u canonical)
					 minutes)))))
			    selected-units)
			   ;; Fall back to smallest unit.
			   (org-last selected-units))))
		(modifier (org-duration--modifier unit canonical)))
	   (concat (format fractional (/ (float minutes) modifier)) unit)))
	;; Otherwise build duration string according to available
	;; units.
	((org-string-nw-p
	  (org-trim
	   (mapconcat
	    (lambda (units)
	      (pcase-let* ((`(,unit . ,required?) units)
			   (modifier (org-duration--modifier unit canonical)))
		(cond ((<= modifier minutes)
		       (let ((value (floor (/ minutes modifier))))
			 (cl-decf minutes (* value modifier))
			 (format " %d%s" value unit)))
		      (required? (concat " 0" unit))
		      (t ""))))
	    selected-units
	    ""))))
	;; No unit can properly represent MINUTES.  Use the smallest
	;; one anyway.
	(t
	 (pcase-let ((`((,unit . ,_)) (last selected-units)))
	   (concat
	    (if (not fractional) "0"
	      (let ((modifier (org-duration--modifier unit canonical)))
		(format fractional (/ (float minutes) modifier))))
	    unit))))))))

;;;###autoload
(defun org-duration-h:mm-only-p (times)
  "Non-nil when every duration in TIMES has \"H:MM\" or \"H:MM:SS\" format.

TIMES is a list of duration strings.

Return nil if any duration is expressed with units, as defined in
`org-duration-units'.  Otherwise, if any duration is expressed
with \"H:MM:SS\" format, return `h:mm:ss'.  Otherwise, return
`h:mm'."
  (let (hms-flag)
    (catch :exit
      (dolist (time times)
	(cond ((string-match-p org-duration--full-re time)
	       (throw :exit nil))
	      ((string-match-p org-duration--mixed-re time)
	       (throw :exit nil))
	      (hms-flag nil)
	      ((string-match-p org-duration--h:mm:ss-re time)
	       (setq hms-flag 'h:mm:ss))))
      (or hms-flag 'h:mm))))


;;; Initialization

(org-duration-set-regexps)

(provide 'org-duration)
;;; org-duration.el ends here