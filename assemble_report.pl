#!/usr/bin/env perl

use strict;
use warnings;

use File::Basename;
use Data::Dumper qw(Dumper);
use Cwd;
use Bio::Seq;
use Bio::SeqIO;

# Usage:
    # assemble_report.pl < full path to fastq files >
    # Files can be zipped or unzipped, single or paired reads
    # Paired files must be labed R1 and R2

print "----- START -----\n\n";

my $path = getcwd;
if (not defined $path) {
    die "ERROR!!! --> Argument to directory containing FASTQ/s was not provided"
}

# place a "/" at the end of path if one not provided
$path =~ s|/?$|/|;
#print "Path to files: $path\n";

# Determine if single or paired read
my @files = < ${path}*fastq* >;
my $read_type;
my $filename;
my $samplename;
# check if array is empty
if (@files) {
    foreach (@files) {
        # get basename
        my $basename = basename($_);
        $filename=$basename;
        chomp $filename;
        ($samplename = $filename) =~ s/_.*//;
        # try to find R[1-2] from basename
        if ($basename =~ /R[1-2]{1}/g) {
            $read_type = "paired";
        } else {
            $read_type = "single";
        }
    }
} else {
    die "ERROR!!! FASTQ not found at $path Look";
}

print "Read type found: $read_type\n\n";

# make zipped and unzipped reads available
use IO::Uncompress::Gunzip qw(gunzip $GunzipError);
use IO::Compress::Gzip qw(gzip $GzipError);
my @files = < ${path}*fastq* >;
foreach my $file (@files) {
    # -B  File is a "binary" file
    # -T  File is an ASCII or UTF-8 text file
    # -e File exists
    # Test if FASTQs are zipped or not.  Make zip and unzip available
    # Binary and text file not present
    # strip .gz
    my $no_gz = substr($file, 0, -3);
        if ( -B $file && ! ( -e $no_gz )) {
        (my $file_noext = $file) =~ s/\.[^.]+$//;
        gunzip $file => $file_noext or die "ERROR!!! gunzip failed for $file";
        }
    my $with_gz = $file . ".gz";
        # Text file and binary not present
    if ( -T $file && ! ( -e $with_gz )) {
        gzip $file => "${file}.gz" or die "gzip failed: $GzipError";
        }
}

# allow to be globally available
# paired reads
my $input_R1_zip;
my $input_R2_zip;
my $input_R1_unzip;
my $input_R2_unzip;
# single reads
my $input_zip;
my $input_unzip;

if ($read_type eq "paired") {
    # place zip and unzipped file into variables
    my @input_R1_zip = < ${path}*R1*fastq.gz >;
    my @input_R2_zip = < ${path}*R2*fastq.gz >;
    my @input_R1_unzip = < ${path}*R1*fastq >;
    my @input_R2_unzip = < ${path}*R2*fastq >;
    foreach (@input_R1_zip) {
        $input_R1_zip = $_;
        }
    foreach (@input_R2_zip) {
        $input_R2_zip = $_;
        }
    foreach (@input_R1_unzip) {
        $input_R1_unzip = $_;
        }
    foreach (@input_R2_unzip) {
        $input_R2_unzip = $_;
        }

    print "Zipped Files:\n";
    print "$input_R1_zip\n";
    print "$input_R2_zip\n\n";

    print "Unzipped Files:\n";
    print "$input_R1_unzip\n";
    print "$input_R2_unzip\n\n";
} else {
    
    my @input_zip = < ${path}*fastq.gz >;
    my @input_unzip = < ${path}*fastq >;
    
    foreach (@input_zip) {
        $input_zip = $_;
    }
    foreach (@input_unzip) {
        $input_unzip = $_;
    }
    
    print "Zipped File:\n";
    print "$input_zip\n";
    
    print "Unzipped File:\n";
    print "$input_unzip\n\n";
}

if ($read_type eq "paired") {
    print "RUNNING SPADES\n\n";
    `spades.py -t 32 -k 45,47,49,51,53,57,59,61,63,65,77,99,127 --careful -1 $input_R1_zip -2 $input_R2_zip -o ./`;
} else {
    print "RUNNING SPADES\n\n";
    `spades.py -t 32 -k 45,47,49,51,53,57,59,61,63,65,77,99,127 --mismatch-correction -s $input_zip -o ./`;
}

print "SPADES IS DONE RUNNING < $samplename >\n";

my $file = < ${path}scaffolds.fasta >;
if (not defined $file) {
    die "### scaffolds file did not create\n"
}

`rm -r K45 K47 K49 K51 K53 K57 K59 K61 K63 K65 K77 K99 K127 misc mismatch_corrector tmp scaffolds.paths assembly_graph.fastg before_rr.fasta contigs.fasta contigs.paths corrected dataset.info input_dataset.yaml params.txt`;

print "scaffolds file: $file";

# LaTeX file
open (my $tex, '>', $samplename . ".tex") or die "$!";

my $frag_size_total=0;
my $counter=0;
my $ave_length;
my $inblast = "$samplename" . "_to_blast.fasta";

my $inseq = Bio::SeqIO->new(-file => $file, -format => "fasta");
my $outseq = Bio::SeqIO->new(-file => ">$inblast", -fomat => 'fasta');
while (my $seq_obj = $inseq->next_seq) {
    $counter++;
    my $length = $seq_obj->length;
    $frag_size_total = $frag_size_total + $length;
    if ( $length > 150 ){
        my $subsequence=$seq_obj->trunc(1,$length-1);
        $outseq->write_seq($subsequence);
    } #else{
        #$outseq->write_seq($seq_obj);
   # }
}

print "\n$counter contigs\n";
$frag_size_total =~ s/(?<=\d)(?=(?:\d\d\d)+\b)/,/g; 
print "Total bases: $frag_size_total\n\n";

my $blast_order = "qlen slen pident mismatch evalue bitscore stitle saccver qseqid";
my $outblast = "$samplename" . "_id.txt";
my $outblast_uniq = "$samplename" . "_id_uniq.txt";
# word_size needs to be set to 11 to return hits for all contigs
`blastn -query $inblast -db /data/BLAST/db/nt -word_size 11 -num_threads 40 -out $outblast -max_target_seqs 1 -outfmt "6 $blast_order"`;

# know bug in -max_target_seqs.  Parameter used within blastn algorithm causing multiple hits to sometimes be returned
`awk -F'\t' '!seen[\$9]++' $outblast > $outblast_uniq`;

# place blast out file into array.  each line and element in list
open ( my $blast_handle, '<', $outblast_uniq) or die "Can't open $outblast_uniq";
chomp(my @lines = <$blast_handle>);
close $blast_handle;

# put accession numbers into list
my @accessions;
foreach my $line (@lines) {
    my @tab = split(/\t/, $line);
    push @accessions, $tab[-2];
}

# count the number each accession occures, put into hash
my %id_count;
my %acc_counts;
my $length_of_contig;
$acc_counts{$_}++ for @accessions;
# for each key in hash
# key = accession number, value = number of occurances
while (my ($key, $value) = each %acc_counts) {
    my $isolate_name;
    # iterate through lines to get isolate name matching accession
    my $count_total_length=0;
    foreach my $line (@lines) {
        my @tab = split(/\t/, $line);    
        if ($key eq $tab[-2]){
            # right to variable, when for multi times will just overwrite
            $isolate_name = $tab[-3];
            # get the total bases identified with uniq accession
            # only works with spades output with length in header
            ($length_of_contig = $tab[-1]) =~ s/.*_length_(.*)_cov.*/$1/;
            #print "length_of_contig: $length_of_contig\n";
            $count_total_length = $count_total_length + $length_of_contig;
            #print "count_total_length: $count_total_length\n";
        }
    }
    # value is the number accession was counted in BLAST output
    # put isolate id and count value into hash for sorting below
    $count_total_length =~ s/(?<=\d)(?=(?:\d\d\d)+\b)/,/g;
    $id_count{"$count_total_length" . " & " . "$isolate_name"} = $value;
}

# output sort
# sorted on count number with id information
# reverse with: {$id_count{$b} <=> $id_count{$a}}

# LaTeX file
 open (my $idtable, '>', $samplename . ".idtable") or die "$!";
foreach my $name (sort {$id_count{$a} <=> $id_count{$b}} keys %id_count) {
    print "$id_count{$name} --> $name\n";
    print $idtable "$id_count{$name} & $name \\\\ \n";
}

# check that blast out elements == in reads, ie number of expected ids output
my $array_size = scalar @lines;
print "The number of top hits: $counter\n";
if ( $counter == $array_size ){
        print "\nPASS -> Records in, match records out\n\n";
    }else{
        print "\n### WARNING read input: $counter uniq BLAST output: $array_size\n\n";
    }

print "\n$counter contigs\n";
print "Total bases: $frag_size_total\n\n";

print "\n$counter contigs\n";
print $idtable "Total bases: $frag_size_total\n\n";

# LaTeX file
open (my $tex, '>', $samplename . ".tex") or die "$!";

my $heredoc = <<'END_MESSAGE';
\documentclass[a4paper,11pt]{article}
\usepackage[margin=0.5in]{geometry}
\usepackage{graphicx}
\usepackage[table]{xcolor}
\usepackage{longtable}

\renewcommand{\thepage}{Appendix --  page \arabic{page}}

\begin{document}

\includegraphics[scale=0.2]{/home/tstuber/report_doc/usdalogo.png}


\today

\vspace{5mm}
\textbf{Whole Genome Sequencing Report:  ${n}} 

\vspace{5mm}

\textbf{File Stats}
\vspace{2mm}

\begin{tabular}{ l | p{7cm} | p{7cm} }
\hline
file name & $forReads & $revReads \\  #sed "s/$n[._]//g" | sed 's/_/\\_/g'
\hline
read count & $forcount & $revcount \\
file size & $forsize & $revsize \\
\hline
\end{tabular}

\vspace{5mm}
\textbf{Assembly}
\vspace{2mm}
\begin{tabular}{ l | l | l | l | l | l | l | p{7cm} }
\hline
# need table here

\hline
\end{tabular}

\vspace{5mm}
\textbf{Identification}
\vspace{2mm}
\begin{longtable}{ l | l | p{13cm} }
\hline
n & accession & identification \\
\hline
# need table here
\hline
\end{longtable}
\end{document}
END_MESSAGE

print $tex "$heredoc";

print "$heredoc";

















print "\n\n### DONE\n\n";
# 2016-12-20 tstuber
