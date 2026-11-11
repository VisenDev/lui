"""Regression tests for the non-evaluating FN normalization used by make lint."""
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from lint import normalize
from lisp_source import definitions


class NormalizationTests(unittest.TestCase):
    def test_typed_parameters_and_setf(self):
        source = '''(fn ((setf size) real)
    ((value real) node &optional ((scale real) 1 supplied)
     &key ((offset real) (+ 1 2)) &aux ((next real) value))
  "Set the scaled size."
  (setf (slot-value node 'size) (+ offset (* scale next))))'''
        result = normalize(source)
        form, parts = next(definitions(result))
        self.assertEqual(parts[1].text(result), '(setf size)')
        self.assertEqual(parts[2].text(result),
                         '(value node &optional (scale 1 supplied) '
                         '&key (offset (+ 1 2)) &aux (next value))')
        for marker in ('"Set the scaled size."', '(setf (slot-value'):
            self.assertEqual(source[:source.index(marker)].count('\n'),
                             result[:result.index(marker)].count('\n'))
        self.assertEqual(form.end, len(result))

    def test_comments_strings_and_quoted_forms_are_untouched(self):
        source = '''; (fn (comment real) () 1)
#| outer #| (fn nested () 1) |# comment |#
(defparameter example "A string\n(fn fake () 1)")
'(fn quoted () 1)
(quote (fn quoted-too () 2))
`(fn template () ,value)
(defparameter characters '(#\\( #\\) #\\; #\\Space))
'''
        self.assertEqual(normalize(source), source)

    def test_conditional_and_nested_definitions(self):
        source = '''#+(or sbcl ecl)
(eval-when (:compile-toplevel :load-toplevel :execute)
  (fn (outer real) ((x real))
    (fn (inner real) ((y real)) (+ x y))
    (inner x)))'''
        result = normalize(source)
        self.assertEqual([parts[0].text(result)
                          for _, parts in definitions(result)],
                         ['defun', 'defun'])
        self.assertIn('(defun outer (x)', result)
        self.assertIn('(defun inner (y)', result)
        self.assertEqual(source.count('\n'), result.count('\n'))

    def test_multiline_defaults_rest_and_untyped_fn(self):
        source = '''(fn collect-items
    ((head string) &optional ((items list) (list head
                                                "second"))
     &rest (others list))
  (append items others))'''
        result = normalize(source)
        self.assertIn('&rest others)', result)
        self.assertIn('(list head\n', result)
        self.assertEqual(source.count('\n'), result.count('\n'))
        self.assertIn('(defun collect-items (head &optional', result)

    def test_uppercase_qualified_fn(self):
        source = '(LUI.FN:FN (F REAL) (&KEY ((X REAL) 3)) X)'
        self.assertEqual(normalize(source), '(defun F (&KEY (X 3)) X)')

    def test_normalization_is_idempotent(self):
        source = '(fn (identity-value t) ((value t)) "Return VALUE." value)'
        self.assertEqual(normalize(normalize(source)), normalize(source))


if __name__ == '__main__':
    unittest.main()
