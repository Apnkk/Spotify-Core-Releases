#!/usr/bin/perl
# Writes the files under a directory (assets/: RootlessJamesDSP's Liveprog scripts and DDC presets) as C, to
# stdout, for JdspBundledFiles.h: the tweak is one dylib with nowhere to keep files of its own, so they are
# compiled into it and copied into the libraries the first time those are made.
#
#     perl embed-assets.pl assets > JdspBundledFiles.c
#
# Each file's kind is the directory it is in (Liveprog, DDC). Every array ends in a NUL the length leaves out,
# so a text file can be read as a C string.
use strict;
use warnings;

my $root = shift or die "usage: embed-assets.pl <dir>\n";
opendir(my $top, $root) or die "cannot open $root: $!\n";
my @kinds = sort grep { !/^\./ && -d "$root/$_" } readdir($top);
closedir($top);

print "// Generated from $root/ by embed-assets.pl. Do not edit.\n";
print "#include \"JdspBundledFiles.h\"\n\n";

my @entries;
my $index = 0;
for my $kind (@kinds) {
    opendir(my $dir, "$root/$kind") or die "cannot open $root/$kind: $!\n";
    my @names = sort grep { !/^\./ && -f "$root/$kind/$_" } readdir($dir);
    closedir($dir);
    for my $name (@names) {
        open(my $file, '<:raw', "$root/$kind/$name") or die "cannot read $root/$kind/$name: $!\n";
        local $/;
        my $bytes = <$file>;
        close($file);
        my @hex = map { sprintf('0x%02x', $_) } unpack('C*', $bytes), 0;
        print "static const unsigned char file$index\[] = {\n";
        for (my $i = 0; $i < @hex; $i += 16) {
            my $last = $i + 15 < $#hex ? $i + 15 : $#hex;
            print '    ', join(', ', @hex[$i .. $last]), ",\n";
        }
        print "};\n";
        (my $cname = $name) =~ s/(["\\])/\\$1/g;
        push @entries, sprintf('    {"%s", "%s", file%d, %d},', $kind, $cname, $index, length($bytes));
        $index++;
    }
}

print "\nconst JdspBundledFile jdspBundledFiles[] = {\n", join("\n", @entries), "\n};\n";
print "const unsigned int jdspBundledFileCount = $index;\n";
