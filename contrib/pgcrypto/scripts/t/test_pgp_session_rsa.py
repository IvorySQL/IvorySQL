#!/usr/bin/env python3
"""Test the generator's pure RSA validation and key serialization functions.

Run: python3 contrib/pgcrypto/scripts/t/test_pgp_session_rsa.py [generator.py]
The source function ASTs are loaded unchanged so this test needs neither
PyCryptodome nor pwntools, which are only needed to generate encrypted data.
"""
import ast
import json
import math
from pathlib import Path
import struct
import sys
import time
import unittest

SCRIPT = Path(sys.argv.pop(1)).resolve() if len(sys.argv) > 1 else (
    Path(__file__).resolve().parents[1] / 'pgp_session_data.py')
FUNCTIONS = {'validate_rsa_key', 'mpi_encode', 'new_packet', 'build_key_data'}
source = ast.parse(SCRIPT.read_text(), filename=str(SCRIPT))
functions = [node for node in source.body
             if isinstance(node, ast.FunctionDef) and node.name in FUNCTIONS]
assert {node.name for node in functions} == FUNCTIONS
namespace = {'struct': struct, 'time': time}
exec(compile(ast.Module(body=functions, type_ignores=[]), str(SCRIPT), 'exec'),
     namespace)
validate = namespace['validate_rsa_key']


class RsaValidation(unittest.TestCase):
    def setUp(self):
        # This public, disposable fixture was generated with OpenSSL. Its
        # exponent was reduced modulo lambda(n), then OpenSSL validated the
        # resulting complete 2048-bit private key. Never use it as a credential.
        fixture = Path(__file__).with_name('rsa-lambda-2048.json')
        self.rsa = {name: int(value, 16)
                    for name, value in json.loads(fixture.read_text()).items()}

    def test_lambda_inverse_2048(self):
        r = self.rsa
        self.assertEqual(r['n'].bit_length(), 2048)
        phi = (r['p'] - 1) * (r['q'] - 1)
        self.assertNotEqual(r['d'] * r['e'] % phi, 1)
        self.assertEqual(r['d'] * r['e'] % math.lcm(r['p'] - 1, r['q'] - 1), 1)
        validate(r)
        for message in (0, 1, 42, r['p'], r['q'], r['n'] - 1):
            with self.subTest(message=message):
                self.assertEqual(pow(pow(message, r['e'], r['n']),
                                     r['d'], r['n']), message)

    def test_small_lambda_inverse(self):
        r = dict(n=55, e=3, d=7, p=5, q=11, u=9)
        validate(r)
        for message in range(r['n']):
            self.assertEqual(pow(pow(message, r['e'], r['n']), r['d'], r['n']),
                             message)

    def test_phi_inverse_remains_valid(self):
        r = dict(self.rsa)
        r['d'] = pow(r['e'], -1, (r['p'] - 1) * (r['q'] - 1))
        validate(r)

    def test_invalid_private_exponent(self):
        self.rsa['d'] += 1
        with self.assertRaisesRegex(ValueError, 'd \\* e'):
            validate(self.rsa)

    def test_other_consistency_checks_remain(self):
        for field in ('n', 'u'):
            with self.subTest(field=field):
                r = dict(self.rsa)
                r[field] += 1
                with self.assertRaises(ValueError):
                    validate(r)
        with self.assertRaisesRegex(ValueError, 'p = q'):
            validate(dict(n=25, e=3, d=7, p=5, q=5, u=1))
        with self.assertRaisesRegex(ValueError, 'gcd'):
            validate(dict(n=55, e=5, d=7, p=5, q=11, u=9))

    def test_validated_key_serializes_as_openpgp(self):
        validate(self.rsa)
        packet = namespace['build_key_data'](self.rsa)
        self.assertEqual(packet[0], 0xC7)  # Secret-subkey packet, new format.
        self.assertTrue(192 <= packet[1] <= 223)
        length = ((packet[1] - 192) << 8) + packet[2] + 192
        body = packet[3:]
        self.assertEqual(len(body), length)
        self.assertEqual(body[0], 4)
        self.assertEqual(body[5], 2)  # RSA encrypt-only algorithm.
        pos = 6
        for field in ('n', 'e', 'd', 'p', 'q', 'u'):
            if field == 'd':
                self.assertEqual(body[pos], 0)  # Unencrypted secret material.
                pos += 1
                private_start = pos
            bits = int.from_bytes(body[pos:pos + 2], 'big')
            pos += 2
            size = (bits + 7) // 8
            value = int.from_bytes(body[pos:pos + size], 'big')
            pos += size
            self.assertEqual(value, self.rsa[field])
            self.assertEqual(bits, value.bit_length())
        self.assertEqual(len(body), pos + 2)
        self.assertEqual(int.from_bytes(body[pos:], 'big'),
                         sum(body[private_start:pos]) & 0xffff)


if __name__ == '__main__':
    unittest.main()
