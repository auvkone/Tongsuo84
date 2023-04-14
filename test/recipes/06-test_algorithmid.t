#! /usr/bin/env perl

# Copyright 2018-2021 The OpenSSL Project Authors. All Rights Reserved.
#
# Licensed under the Apache License 2.0 (the "License").  You may not use
# this file except in compliance with the License.  You can obtain a copy
# in the file LICENSE in the source distribution or at
# https://www.openssl.org/source/license.html

use strict;

use File::Path 2.00 qw/rmtree/;
use OpenSSL::Test qw(:DEFAULT cmdstr srctop_file);
use OpenSSL::Test::Utils;

setup("test_algorithmid");

# eecert => cacert
my %certs_info =
    (
     'ee-cert' => 'ca-cert',
     'ee-cert2' => 'ca-cert2',

     # 'ee-pss-sha1-cert' => 'ca-cert',
     # 'ee-pss-sha256-cert' => 'ca-cert',
     # 'ee-pss-cert' => 'ca-pss-cert',
     # 'server-pss-restrict-cert' => 'rootcert',

     (
      disabled('ec')
      ? ()
      : (
         'ee-cert-ec-explicit' => 'ca-cert-ec-named',
         'ee-cert-ec-named-explicit' => 'ca-cert-ec-explicit',
         'ee-cert-ec-named-named' => 'ca-cert-ec-named',
         # 'server-ed448-cert' => 'root-ed448-cert'
         'server-ecdsa-brainpoolP256r1-cert' => 'rootcert',
        )
     )
    );
my @pubkeys =
    (
     'testrsapub',
     disabled('dsa') ? () : 'testdsapub',
     disabled('ec') ? () : qw(testecpub-p256 tested25519pub tested448pub)
    );
my @certs = sort keys %certs_info;

plan tests =>
    scalar @certs
    + scalar @pubkeys
    + 1;

foreach (@certs) {
    ok(run(test(['algorithmid_test', '-x509',
                 srctop_file('test', 'certs', "$_.pem"),
                 srctop_file('test', 'certs', "$certs_info{$_}.pem")])));
}

foreach (sort @pubkeys) {
    ok(run(test(['algorithmid_test', '-spki', srctop_file('test', "$_.pem")])));
}

subtest 'Check SM2 algorithm id' => sub {
    SKIP: {
        plan skip_all => "SM2 is not supported by this OpenSSL build"
            if disabled("sm2");

        my $cnf = srctop_file("test","ca-and-certs.cnf");
        my $cakey = srctop_file("test", "certs", "ca-key.pem");

        $ENV{OPENSSL} = cmdstr(app(["openssl"]), display => 1);
        $ENV{OPENSSL_CONFIG} = qq(-config "$cnf");

        rmtree("demoCA", { safe => 0 });

        ok(run(perlapp(["CA.pl", "-newca", "-extra-req", "-key $cakey"],
                       stdin => undef)),
           'creating CA structure');

        ok(run(app(["openssl", "ca", "-config",
                    $cnf,
                    "-in", srctop_file("test", "certs", "sm2-csr.pem"),
                    "-out", "sm2-test.crt",
                    "-sigopt", "distid:1234567812345678",
                    "-vfyopt", "distid:1234567812345678",
                    "-md", "sm3",
                    "-batch",
                    "-cert",
                    srctop_file("test", "certs", "sm2-root.crt"),
                    "-keyfile",
                    srctop_file("test", "certs", "sm2-root.key")])),
           "Sign SM2 certificate");

        ok(run(test(['algorithmid_test', '-x509', "sm2-test.crt",
                      srctop_file('test', 'certs', "sm2-root.crt")])));

        # SM2 key generated by ecparam
        ok(run(app(["openssl", "ecparam", "-genkey", "-name", "sm2", "-out",
                    "sm2-ecparam.key"])), "generate sm2 private key");
        ok(run(app(["openssl", "ec", "-in", "sm2-ecparam.key", "-pubout",
                    "-out", "sm2pub-ecparam.key"])), "generate sm2 pub key");
        ok(run(test(['algorithmid_test', '-spki', "sm2pub-ecparam.key"])));

        # SM2 key generated by ecparam with explicit param
        ok(run(app(["openssl", "ecparam", "-genkey", "-name", "sm2",
                    "-param_enc", "explicit", "-out", "sm2-ecparam-explicit.key"
                    ])), "generate sm2 private key with explicit param");
        ok(run(app(["openssl", "ec", "-in", "sm2-ecparam-explicit.key",
                    "-pubout", "-out", "sm2pub-ecparam-explicit.key"])),
                    "generate sm2 pub key with explicit param");
        ok(run(test(['algorithmid_test', '-spki', "sm2pub-ecparam-explicit.key"]
                    )));

        # SM2 key generated by genpkey
        ok(run(app(["openssl", "genpkey", "-algorithm", "ec", "-pkeyopt",
                    "ec_paramgen_curve:sm2", "-out", "sm2-genpkey.key"])),
           "generate sm2 private key");
        ok(run(app(["openssl", "pkey", "-in", "sm2-genpkey.key", "-pubout",
                    "-out", "sm2pub-genpkey.key"])), "generate sm2 pub key");
        ok(run(test(['algorithmid_test', '-spki', "sm2pub-genpkey.key"])));

        # SM2 key generated by genpkey with explicit param
        ok(run(app(["openssl", "genpkey", "-algorithm", "ec", "-pkeyopt",
                    "ec_paramgen_curve:sm2", "-pkeyopt",
                    "ec_param_enc:explicit", "-out",
                    "sm2-genpkey-explicit.key"])),
           "generate sm2 private key with explicit param");
        ok(run(app(["openssl", "pkey", "-in", "sm2-genpkey-explicit.key",
                    "-pubout", "-out", "sm2pub-genpkey-explicit.key"])),
           "generate sm2 pub key with explicit param");
        ok(run(test(['algorithmid_test', '-spki', "sm2pub-genpkey-explicit.key"]
                    )));
    }
}