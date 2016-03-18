#!/usr/bin/perl

# --------------------------------------------------------------------
# %% Setting up %%
#

use strict;
use Getopt::Long qw(:config no_ignore_case no_auto_abbrev pass_through);
use File::Temp qw/ tempfile tempdir /;
use Bio::SeqIO;
use Bio::Seq;
use Bio::SearchIO;
use Try::Tiny::Retry;

use constant PROGRAM_NAME            => 'VirulenceFinder_1.4.pl';
use constant PROGRAM_NAME_LONG       => 'Finds antimicrobial resitance genes for a sequence or genome';
use constant VERSION                 => '1.4';

#Global variables
my $BLAST;
my $BLASTALL;
my $FORMATDB;
my $ABRES_DB;
my $Notes1;
my ($Help, $AB_input, $threshold,$InFile, $dir);
my $IFormat = "fasta";
my $OFormat = "ST";
my %ARGV    = ('-p' => 'blastn', '-a' => '5' , '-F' => 'F');

#Getting global variables from the command line
&commandline_parsing();

if (defined $Help || not defined $AB_input || not defined $InFile || not defined $threshold) {
   print_help();
   exit;
}

#If there are not given a path to the database or BLAST the program assume that the files are located in the curet directury
if (not defined $BLAST) {
   $BLASTALL = "blastall";
   $FORMATDB = "formatdb";
}
if (not defined $ABRES_DB) {
  $ABRES_DB = "database";
  $Notes1 = "database/notes.txt";
}
if (not defined $dir) {
  $dir = ".";
}


# --------------------------------------------------------------------

# %% Main Program %%
#
## AVAILABLE antimicrobial familyes ##
  # hash mapping the ARGF profiles to antibiotic names
my %argfProfiles=();
##################### Antimicrobial familyes ################# ="Aminoglycoside";
#$argfProfiles{"virulence_vtec"} ="VTEC";
#$argfProfiles{"virulence_vtec_extended"} ="Other virulence genes - E. Coli";
#$argfProfiles{"virulence_hhas"} ="Virulence - TEST HHAS";
#$argfProfiles{"virulence_fmaa"} ="Virulence - TEST FMAA";
$argfProfiles{"virulence_ENT"} ="Virulence - Enterococcus";
$argfProfiles{"virulence_ecoli"} ="Virulence - E. coli";
$argfProfiles{"s.aureus_enterotoxin"} ="S. aureus - Enterotoxin";
$argfProfiles{"s.aureus_exoenzyme"} ="S. aureus - Exoenzyme";
$argfProfiles{"s.aureus_hostimm"} ="S. aureus - Host Immune evasion";
#$argfProfiles{"s.aureus"} ="S. aureus";
# -----------------------
#Making phenotype list
my %Notes_hash = &phenolist($Notes1);

#For alignment
my %GENE_ALIGN_HIT_HASH; #will contain the sequence alignment lines
my %GENE_ALIGN_HOMO_HASH; #will contain the sequence alignment homolog string
my %GENE_ALIGN_QUERY_HASH; #will contain the sequence alignment allele string
my %GENE_RESULTS_HASH2;
my %FINAL_RESULTS; # will contain the results for txt printing

### Variables for text-printing ###
my $txtresults= "VirulenceFinder result file\n\n"; #Added to txt print
my $tabr .= "Virulence factor\tIdentity\tQuery/HSP\tContig\tPosition in contig\tProtein function\tAccession no.\n"; #added to print tab-separated txt file
my  $contigtable ="\nContig Table\n"; #added to txt print
$contigtable .= "-----------\n";
my $Virulencetable ="\nVirulence Factor\tProtein Function\n";
$Virulencetable .= "_________________________________________________________________________________\n";
my $alignment = "\n\nAlignments as text\n_________________________________________________________________________________\n";
my @headarray = ("VIRULENCE FACTOR  ", "IDENTITY  ", "QUERY/HSP     ", "CONTIG  ", "POSITION         ", "ACC NO.         ");
my $resalign = ""; #Added for alignment print
my $hits_in_seq = ""; #Added for alignment print

# Finding genes for each chosen antimicrobial family
my $antibiocount = 0;
my @Antimicrobial = split(/,/,$AB_input);
foreach my $element(@Antimicrobial){
  # print "$element\n";
  $antibiocount ++;
  my $CurrentAnti = $element;
  
  
  # Run BLAST and find best matching Alleles
  my ($Seqs_ABres, $Seqs_input, @Blast_lines);
  
  retry{
      $Seqs_ABres   = read_seqs(-file => $ABRES_DB.'/'.$element.'.fsa', format => 'fasta');  
      $Seqs_input  = $InFile ne "" ? read_seqs(-file => $InFile, -format => $IFormat) : 
                                  read_seqs(-fh => \*STDIN,   -format => $IFormat);
   
      @Blast_lines = get_blast_run(-d => $Seqs_input, -i => $Seqs_ABres, %ARGV)
   }
   catch{ die $_ };
 
  # Declaring variables for each BLAST
  #Declaring variables - array and hash
  my @RESULTS_AND_SETTINGS_ARRAY; #will contain the typing results some setting and the hash with the results for each gene
  my @GENE_RESULTS_ARRAY; #will contain the typing results some setting and the hash with the results for each gene
  #my %GENE_ALIGN_HIT_HASH; #will contain the sequence alignment lines
  #my %GENE_ALIGN_HOMO_HASH; #will contain the sequence alignment homolog string
  #my %GENE_ALIGN_QUERY_HASH; #will contain the sequence alignment allele string
  my %GENE_RESULTS_HASH;
  my %ABres;
  my %GENEID;
  my %BITS;
  my %PERC_IDENT;
  my %QUERY_LENGTH;
  my %HSP_LENGTH;
  my %GAPS;
  my %Q_STRING;
  my %HIT_STRING;
  my %HOMO_STRING;
  my %CONTIG_NAME;
  my %HIT_STRAND;
  my %HIT_END;
  my %QUERY_START;
  my %HIT_START;
  my %HIT_LENGTH;
  my %HoA_sort; # Hash of hashes, dividing results for each contig
  my @best_hit;

  for my $blast_line (@Blast_lines) {  # Notice that a properly formatted mlst blastdb will have the gene name as the description and the allele as id
    chomp $blast_line;
    my @blast_elem = split ("\t",$blast_line);
    my $qid = $blast_elem[0];
    my $query_length = $blast_elem[1];
    my $hsp_length = $blast_elem[2];
    my $gaps = $blast_elem[3];
    my $ident = $blast_elem[4];
    my $e = $blast_elem[5];
    my $bits = $blast_elem[6];
    my $calc_score = $query_length - $hsp_length + $gaps + 1; #Notice that I add 1 to the calc_score since I later need it to evaluate to true, which 0 wouldn't.
    my $q_string = $blast_elem[7];
    my $hit_string = $blast_elem[8];
    my $homo_string = $blast_elem[9];
    my @seq_inds = $blast_elem[10];
    my $hit_strand = $blast_elem[11];
    my $hit_start = $blast_elem[12];
    my $hit_end = $blast_elem[13];
    my $contig_name = $blast_elem[14];
    my $query_strand = $blast_elem[15];
    my $query_start = $blast_elem[16];
    my $hit_length = $blast_elem[17];
    my $id = $hit_start."_".$hit_end."_".$contig_name;
    # print "1- $qid, $query_length, $hsp_length, $ident, $e, $bits, $calc_score, $q_string, $hit_string, $homo_string, $hit_strand, $hit_start, $hit_end, $gaps, $contig_name, $query_strand, $query_start\n"; 
  
    # Save BLAST results, sorting on position and contig
    if (exists $BITS{$id}){
      #print "if exists, BITS{id}: $BITS{$id}, bits: $bits, qid: $qid\n";
      if ($calc_score == $ABres{$id} and $bits > $BITS{$id}) {
        $ABres{$id}  = $calc_score; #%MLST and %PERC_IDENT are later used to find the best query ID at the next level (adk1.., adk2.., adk3.. ->  dk2..). 
        $GENEID{$id} = $qid; #Query ID, genename_connecter_accessionnumber, e.g. tet(C)_2_AB123456
        $BITS{$id} = $bits; # Bit score, used later to sort BLAST hits
        $PERC_IDENT{$id}  = $ident; # Procent identity
        $QUERY_LENGTH {$id}  = $query_length; #%QUERY_LENGTH, %HSP_LENGTH, and %GAPS are outputted, if the match is not perfect
        $HSP_LENGTH{$id}  = $hsp_length; # length of hsp
        $GAPS{$id} = $gaps; # gaps
        $Q_STRING{$id} = $q_string; # 
        $HIT_STRING{$id} = $hit_string;
        $HOMO_STRING{$id} = $homo_string;
        $QUERY_START{$id} = $query_start;
        $CONTIG_NAME{$id} = $contig_name ;
        $HIT_STRAND{$id} = $hit_strand ;
        $HIT_START{$id} = $hit_start;
        $HIT_END{$id} = $hit_end;
        $HIT_LENGTH{$id} = $hit_length;
        # Making HoA to sort hit with overlapping positions
        $HoA_sort{$contig_name}->{$id} = [$hit_start,$hit_end,$contig_name,$qid,$bits,$calc_score];
      } elsif ($bits > $BITS{$id}){
        $ABres{$id}  = $calc_score; #%MLST and %PERC_IDENT are later used to find the best query ID at the next level (adk1.., adk2.., adk3.. ->  dk2..). 
        $GENEID{$id} = $qid; #Query ID, genename_connecter_accessionnumber, e.g. tet(C)_2_AB123456
        $BITS{$id} = $bits; # Bit score, used later to sort BLAST hits
        $PERC_IDENT{$id}  = $ident; # Procent identity
        $QUERY_LENGTH {$id}  = $query_length; #%QUERY_LENGTH, %HSP_LENGTH, and %GAPS are outputted, if the match is not perfect
        $HSP_LENGTH{$id}  = $hsp_length; # length of hsp
        $GAPS{$id} = $gaps; # gaps
        $Q_STRING{$id} = $q_string; # 
        $HIT_STRING{$id} = $hit_string;
        $HOMO_STRING{$id} = $homo_string;
        $QUERY_START{$id} = $query_start;
        $CONTIG_NAME{$id} = $contig_name ;
        $HIT_STRAND{$id} = $hit_strand ;
        $HIT_START{$id} = $hit_start;
        $HIT_END{$id} = $hit_end;
        $HIT_LENGTH{$id} = $hit_length;
        $HoA_sort{$contig_name}->{$id} = [$hit_start,$hit_end,$contig_name,$qid,$bits,$calc_score];
      } 
    } else {
      #print "else\t$qid\n";
      $ABres{$id}  = $calc_score; #
      $GENEID{$id} = $qid; #Query ID, genename_connecter_accessionnumber, e.g. tet(C)_2_AB123456
      $BITS{$id} = $bits; # Bit score, used later to sort BLAST hits
      $PERC_IDENT{$id}  = $ident; # Procent identity
      $QUERY_LENGTH {$id}  = $query_length; #%QUERY_LENGTH, %HSP_LENGTH, and %GAPS are outputted, if the match is not perfect
      $HSP_LENGTH{$id}  = $hsp_length; # length of hsp
      $GAPS{$id} = $gaps; # gaps
      $Q_STRING{$id} = $q_string; # 
      $HIT_STRING{$id} = $hit_string;
      $HOMO_STRING{$id} = $homo_string;
      $QUERY_START{$id} = $query_start;
      $CONTIG_NAME{$id} = $contig_name ;
      $HIT_STRAND{$id} = $hit_strand ;
      $HIT_START{$id} = $hit_start;
      $HIT_END{$id} = $hit_end;
      $HIT_LENGTH{$id} = $hit_length;
      $HoA_sort{$contig_name}->{$id} = [$hit_start,$hit_end,$contig_name,$qid,$bits,$calc_score];
    }
  }

  #my @best_hit;
  #Saving the best hits in each contig for each porsition
  foreach my $contig (keys %HoA_sort){
    #print "First level: $contig\n";
    my @list;
    my $k = 0;
    foreach ( keys %{$HoA_sort{$contig}} ) {
      my $hit = $_;
      #print "Second level: $hit\n";
      foreach my $i ( 0 .. $#{ $HoA_sort{$contig}{$hit} } ) {
        #print "Third level: $HoA_sort{$contig}{$hit}[$i]\t";
        push (@{$list[$k]},  $HoA_sort{$contig}{$hit}[$i]);
      }
      #print "\n\n";
      $k++;
    }
  
    #Sorting AoA aftener start position in contig
    my @sorted = sort { $a->[0] <=> $b->[0] } @list;
    
    #Sorting, so overlapping genes are removed
    my $start = 0;
    my $end = 1;
    my $contig = 2;
    my $bits = 4;
    my $calc_score = 5;
    my $first = 0;
    my $next = 1;
    # If only one hit is found in the contig
    if ($#sorted == 0) {
      push(@best_hit, "$sorted[0][0]_$sorted[0][1]_$sorted[0][2]");
    }
    until ($next > $#sorted ) { # så længe $first <= 4 og $next <= 5
      if ($#sorted == 1) {
        if ($sorted[$first][$bits] >= $sorted[$next][$bits]) {
          push (@best_hit, "$sorted[$first][$start]_$sorted[$first][$end]_$sorted[$first][$contig]");
          #print "Sorted == 1, first: $sorted[$first][$start]_$sorted[$first][$end]_$sorted[$first][$contig]";
          $next++
        } else {
          push (@best_hit, "$sorted[$next][$start]_$sorted[$next][$end]_$sorted[$next][$contig]");
          #print "Sorted == 1, next: $sorted[$next][$start]_$sorted[$next][$end]_$sorted[$next][$contig]";
          $next++;
        }
      }
      if ($sorted[$first][$end] <= $sorted[$next][$start]) { # If first end is before next start
        if ($next == $#sorted) {
          push (@best_hit, "$sorted[$first][$start]_$sorted[$first][$end]_$sorted[$first][$contig]");
          push (@best_hit, "$sorted[$next][$start]_$sorted[$next][$end]_$sorted[$next][$contig]");
          #print "if end<start, first: $first, next: $next\t$sorted[$first][$start]_$sorted[$first][$end]_$sorted[$first][$contig]\t$sorted[$next][$start]_$sorted[$next][$end]_$sorted[$next][$contig]\n";
          $first = $next;
          $next++;
        } else {
          push (@best_hit, "$sorted[$first][$start]_$sorted[$first][$end]_$sorted[$first][$contig]");
          #print "if end<start, first: $first, next: $next\t$sorted[$first][$start]_$sorted[$first][$end]_$sorted[$first][$contig]\n";
          $first = $next;
          $next++;
        }        
      }
      elsif ( ($sorted[$first][$end] >= $sorted[$next][$start]+1) && ($sorted[$first][$end] < $sorted[$next][$start]+30)) { # overlap 1-30, ŒVancomycin A-H overlap 3, 7, 10, 17, 22
        push (@best_hit, "$sorted[$first][$start]_$sorted[$first][$end]_$sorted[$first][$contig]");
        #print "if +1-30, first: $first, next: $next\tsave: $sorted[$first][$start]_$sorted[$first][$end]_$sorted[$first][$contig]\n";
        $first = $next;
        $next++;
      }
      elsif (($sorted[$first][$end] > $sorted[$next][$start]) && ($sorted[$first][$calc_score] < $sorted[$next][$calc_score])){ # If first end is after next start + first is better...
        if ($next == $#sorted){
          push (@best_hit, "$sorted[$first][$start]_$sorted[$first][$end]_$sorted[$first][$contig]");
          #print "1>2: $next\n";
          $next++;
        } else {
          #print "1>2: first: $first, next: $next\n";
          $next++;
        }
      } 
      elsif (($sorted[$first][$end] > $sorted[$next][$start]) && ($sorted[$first][$calc_score] > $sorted[$next][$calc_score])) { #If first end is after next start + next is better...
        if ($next == $#sorted){
          push (@best_hit, "$sorted[$next][$start]_$sorted[$next][$end]_$sorted[$next][$contig]");
          #print "1<=2: $next\n";
          $next++;
        } else {
          #print "1<=2: first: $first, next: $next\n";
          $first = $next;
          $next++;
        }  
      }
      elsif (($sorted[$first][$end] > $sorted[$next][$start]) && ($sorted[$first][$calc_score] == $sorted[$next][$calc_score])) { # If Calc_score ==
        if ($sorted[$first][$bits] > $sorted[$next][$bits]) { # First bits > next bits => first better
          if ($next == $#sorted){
            push (@best_hit, "$sorted[$first][$start]_$sorted[$first][$end]_$sorted[$first][$contig]");
            #print "1>2: $next\n";
            $next++;
          } else {
            #print "1>2: first: $first, next: $next\n";
            $next++;
          }
        } 
        elsif ($sorted[$first][$bits] <= $sorted[$next][$bits]) { # Next bits > first bits => next better...
          if ($next == $#sorted){
            push (@best_hit, "$sorted[$next][$start]_$sorted[$next][$end]_$sorted[$next][$contig]");
            #print "1<=2: $next\n";
            $next++;
          } else {
            #print "1<=2: first: $first, next: $next\n";
            $first = $next;
            $next++;
          }  
        } 
      }
      elsif ($next == $#sorted){
        #print "First = length: first: $first, next: $next\t";
        push (@best_hit, "$sorted[$first][$start]_$sorted[$first][$end]_$sorted[$first][$contig]");
        $next++;
      }
    }
  }

  my @control;
  my $major_variants_detector = 0;
  foreach my $gene (@best_hit){
    #print "Gene: $gene\t$Profile{$gene}->{gene}\t"; # $gene = $genename (tet(A)), $Profile{$gene}->{gene} = header in fastafile (tet(A)_1_AC12345)
    my $data = $gene;

    #Get accession number
    my @tmp = split(/:/, $GENEID{$gene},4);
    my $accNR = $tmp[2];
    my $stx = $tmp[3];
    my $genename = $tmp[0];
    my $note = "$genename$stx";
    #print "Acc: $accNR\t stx: $stx\tnote: $note\tgene: $gene\n";
  
    $GENE_RESULTS_HASH{$gene} = ();
    $GENE_ALIGN_HIT_HASH{$gene} = ();
    $GENE_ALIGN_HOMO_HASH{$gene} = ();
    $GENE_ALIGN_QUERY_HASH{$gene} = ();

    #Declaring variables
    my $sub_contig;
    my $sub_rev_contig;
    my $final_contig;
    my $spaces_hit;
    my $spaces_match_string;
    my $seq_lower_case;
    my $final_seq_lower_case;
    my $variant = "None";
    my @gaps_in_gene;
    my @gaps_in_hit;
    my $no_gaps_gene = 0;
    my $no_gaps_hit = 0;

    # Position in contig
    my $position = "$HIT_START{$data}..$HIT_END{$data}";
  
   #Finding genes with a %ID >= threshold, savning results for output-print in html
    if ($HSP_LENGTH{$data} >= (3/5)*$QUERY_LENGTH{$data} and $PERC_IDENT{$data} >= $threshold) {
      push(@control, $data);
      if ($HSP_LENGTH{$data} == $QUERY_LENGTH{$data} and $PERC_IDENT{$data} == 100.00){ #If 100% length and %id = 100
        push(@{$GENE_RESULTS_HASH{$gene}}, "perfect");
        push(@{$GENE_RESULTS_HASH2{$gene}}, "perfect");
        #print "Perfect - $gene\n";
        my $notes_1;
        if (exists $Notes_hash{$note}){
          $notes_1 = $Notes_hash{$note};
        } #End if (exists $Pheno_hash{$gene})
        push(@{$GENE_RESULTS_HASH{$gene}},sprintf("%.2f", $PERC_IDENT{$data})); #% ID
        push(@{$GENE_RESULTS_HASH{$gene}}, $QUERY_LENGTH{$data}); # Query lenght
        push(@{$GENE_RESULTS_HASH{$gene}}, $HSP_LENGTH{$data}); # HSP langht
        push(@{$GENE_RESULTS_HASH{$gene}}, $CONTIG_NAME{$data}); # Name of Contig
        push(@{$GENE_RESULTS_HASH{$gene}}, $position); # Start..END position in contig
        push(@{$GENE_RESULTS_HASH{$gene}}, $GENEID{$gene}); # e.g. tet(A)_2_AC12345
        push(@{$GENE_RESULTS_HASH{$gene}}, $notes_1); #Note omkring virulence factor
        push(@{$GENE_RESULTS_HASH{$gene}}, $accNR); #Accession number
        push(@{$GENE_RESULTS_HASH{$gene}}, $genename); # Genename, e.g. tet(A)
        $final_seq_lower_case = $Q_STRING{$data}; #for printing alignment
        $final_contig = $HIT_STRING{$data}; #for printing alignment
        # for alignment
        push(@{$GENE_RESULTS_HASH2{$gene}},sprintf("%.2f", $PERC_IDENT{$data})); #% ID
        push(@{$GENE_RESULTS_HASH2{$gene}}, $QUERY_LENGTH{$data}); # Query lenght
        push(@{$GENE_RESULTS_HASH2{$gene}}, $HSP_LENGTH{$data}); # HSP langht
        push(@{$GENE_RESULTS_HASH2{$gene}}, $CONTIG_NAME{$data}); # Name of Contig
        push(@{$GENE_RESULTS_HASH2{$gene}}, $position); # Start..END position in contig
        push(@{$GENE_RESULTS_HASH2{$gene}}, $QUERY_START{$data}); #
        push(@{$GENE_RESULTS_HASH2{$gene}}, $genename); # Genename, e.g. tet(A)
      } 
      elsif ($HSP_LENGTH{$data} == $QUERY_LENGTH{$data} and $PERC_IDENT{$data} < 100.00) { #If length !=
        push(@{$GENE_RESULTS_HASH{$gene}}, "warning1");
        push(@{$GENE_RESULTS_HASH2{$gene}}, "warning1");
        #print "Warning1 - $gene\n";
        my $notes_1;
        if (exists $Notes_hash{$note}){
          $notes_1 = $Notes_hash{$note};
        } #End if (exists $Pheno_hash{$gene})
        push(@{$GENE_RESULTS_HASH{$gene}},sprintf("%.2f", $PERC_IDENT{$data})); #% ID
        push(@{$GENE_RESULTS_HASH{$gene}}, $QUERY_LENGTH{$data}); # Query lenght
        push(@{$GENE_RESULTS_HASH{$gene}}, $HSP_LENGTH{$data}); # HSP langht
        push(@{$GENE_RESULTS_HASH{$gene}}, $CONTIG_NAME{$data}); # Name of Contig
        push(@{$GENE_RESULTS_HASH{$gene}}, $position); # Start..END position in contig
        push(@{$GENE_RESULTS_HASH{$gene}}, $GENEID{$gene}); # e.g. tet(A)_2_AC12345
        push(@{$GENE_RESULTS_HASH{$gene}}, $notes_1); #Phenotype
        push(@{$GENE_RESULTS_HASH{$gene}}, $accNR); #Accession number
        push(@{$GENE_RESULTS_HASH{$gene}}, $genename); # Genename, e.g. tet(A)
        $seq_lower_case = $Q_STRING{$data}; #for printing alignment
        $final_contig = $HIT_STRING{$data}; #for printing alignment
        # For alignment
        push(@{$GENE_RESULTS_HASH2{$gene}},sprintf("%.2f", $PERC_IDENT{$data})); #% ID
        push(@{$GENE_RESULTS_HASH2{$gene}}, $QUERY_LENGTH{$data}); # Query lenght
        push(@{$GENE_RESULTS_HASH2{$gene}}, $HSP_LENGTH{$data}); # HSP langht
        push(@{$GENE_RESULTS_HASH2{$gene}}, $CONTIG_NAME{$data}); # Name of Contig
        push(@{$GENE_RESULTS_HASH2{$gene}}, $position); # Start..END position in contig
        push(@{$GENE_RESULTS_HASH2{$gene}}, $QUERY_START{$data});
        push(@{$GENE_RESULTS_HASH2{$gene}}, $genename); # Genename, e.g. tet(A)
      
        #Identifying gaps in the MLST allele string and hit string
        @gaps_in_gene = Getting_gaps($Q_STRING{$data});
        @gaps_in_hit = Getting_gaps($HIT_STRING{$data});
        #foreach my $elem (@gaps_in_hit){
        #print "####\n$elem\n#####";
        #}
    
        $no_gaps_gene = scalar @gaps_in_gene;
        $no_gaps_hit = scalar @gaps_in_hit;

        #Getting the complete mlst allele (even thought it may not all be part of the HSP)   
        my @array_for_getting_mlst_seq = ($GENEID{$data});
        my $Seqs_ref = grep_ids(-seqs => $Seqs_ABres, -ids => \@array_for_getting_mlst_seq);  
        for (@{ $Seqs_ref }) {
          $seq_lower_case = lc($_->seq);
        }
    
        #Getting the right contig
        my @array_for_getting_genome_seq = ($CONTIG_NAME{$data});
        my $Seqs_genome_ref = grep_ids(-seqs => $Seqs_input, -ids => \@array_for_getting_genome_seq);  
        for (@{ $Seqs_genome_ref }) {
          my $contig = lc($_->seq);
          my $length_contig = length($contig);  #Redundant, da jeg også v.h.a. bioperl finder hit length
       
          #Getting the right sub_contig depends on which strand the hit is on
          #If the hit is on the +1 
          if ($HIT_STRAND{$data} == 1){
            if (($QUERY_START{$data} == 1) && (($QUERY_LENGTH{$data} + $no_gaps_gene) == $HSP_LENGTH{$data})){  
              $variant = 1;
              $sub_contig = substr($contig, ($HIT_START{$data} - 1 ),  ($HSP_LENGTH{$data} - $no_gaps_hit) );
            }
            elsif (($QUERY_START{$data} == 1) && (($QUERY_LENGTH{$data} + $no_gaps_gene) > $HSP_LENGTH{$data})) { 
              if (($HIT_START{$data} + ($QUERY_LENGTH{$data} + $no_gaps_gene)) > ($length_contig + $no_gaps_hit)){ 
                $variant = 2;
                $major_variants_detector = 1;
                $sub_contig = substr($contig, ($HIT_START{$data} - 1 ),  $HSP_LENGTH{$data});
              }
              elsif (($HIT_START{$data} + ($QUERY_LENGTH{$data} + $no_gaps_gene)) <= ($length_contig + $no_gaps_hit)) {
                $variant = 3;
                $sub_contig = substr($contig, ($HIT_START{$data} - 1 ),  ($QUERY_LENGTH{$data} + $no_gaps_gene - $no_gaps_hit));
              }
            }
            elsif ($QUERY_START{$data} > 1){
              if (($HIT_START{$data} - $QUERY_START{$data}) < 0){
                $variant = 4;
                $major_variants_detector = 1;
                $sub_contig = substr($contig, 0,  ( $HIT_START{$data} + (($QUERY_LENGTH{$data} + $no_gaps_gene) - $QUERY_START{$data})));
                #If, as here, the HSP only starts some nucleotides within the mlst allele, a number of spaces must be written before the matching string from the genome. Likewise, the match-string (the "|| ||| ||") should be preceeded by spaces
                $spaces_hit = $QUERY_START{$data} - $HIT_START{$data} + 1;
                $spaces_match_string = $QUERY_START{$data};
              }
              else {    
                if ((($HIT_START{$data} - $QUERY_START{$data}) + ($QUERY_LENGTH{$data} + $no_gaps_gene)) < ($HIT_LENGTH{$data} + $no_gaps_hit)){
                  $variant = "5a";
                  $sub_contig = substr($contig, ($HIT_START{$data} - $QUERY_START{$data}), ($QUERY_LENGTH{$data} + $no_gaps_gene));
                  $spaces_match_string = $QUERY_START{$data};
                }
                else {
                  $variant = "5b";
                  $major_variants_detector = 1;
                  $sub_contig = substr($contig, ($HIT_START{$data} - $QUERY_START{$data}),  ((($HIT_LENGTH{$data} + $no_gaps_hit) - $HIT_START{$data}) + $QUERY_START{$data} -1 ));
                  $spaces_match_string = $QUERY_START{$data};
                }
              }
            }
            else {
              #print "New option not taken into account!\n";
            }
          } 
       
          #If the hit is on the -1 strand
          elsif ($HIT_STRAND{$data} == -1){
            if (($QUERY_START{$data} == 1) && (($QUERY_LENGTH{$data} + $no_gaps_gene) == $HSP_LENGTH{$data})){
              $variant = 6;
              $sub_contig = substr($contig, ($HIT_START{$data} - 1 ), ($HSP_LENGTH{$data} - $no_gaps_hit));
            }
            elsif (($QUERY_START{$data} == 1) && (($QUERY_LENGTH{$data} + $no_gaps_gene ) > $HSP_LENGTH{$data})) {
              if(($HIT_START{$data}-(($QUERY_LENGTH{$data} + $no_gaps_gene) - ($HSP_LENGTH{$data} - $no_gaps_hit))) >= 0){
                $variant = 7;
                $sub_contig = substr($contig, ($HIT_START{$data}-(($QUERY_LENGTH{$data} + $no_gaps_gene) - ($HSP_LENGTH{$data} - $no_gaps_hit))) - 1,  (($QUERY_LENGTH{$data} + $no_gaps_gene )));
              }
              elsif (($HIT_START{$data}-(($QUERY_LENGTH{$data} + $no_gaps_gene ) - ($HSP_LENGTH{$data} - $no_gaps_hit))) < 0){
                $variant = 8;
                $major_variants_detector = 1;
                $sub_contig = substr($contig, 0 , ($HIT_START{$data} + ($HSP_LENGTH{$data}- $no_gaps_hit) -1));
              }
            }
            elsif ($QUERY_START{$data} > 1){
              if (($HIT_START{$data} + $QUERY_LENGTH{$data}) > $length_contig){ 
                #If, as here, the HSP only starts some nucleotides within the mlst allele, a number of spaces must be written before the matching string from the genome
                $variant = 10;
                $major_variants_detector = 1;
                $spaces_hit = $QUERY_START{$data} - ($length_contig - $HIT_END{$data}) ;
                $spaces_match_string = $QUERY_START{$data};
                $sub_contig = substr($contig, ($HIT_START{$data} -1 - ($QUERY_LENGTH{$data} - $HSP_LENGTH{$data} - $QUERY_START{$data}+1)), ((($QUERY_LENGTH{$data} - $QUERY_START{$data})+($length_contig - $HIT_END{$data}))+1));
              }
              elsif (($HIT_START{$data} + $QUERY_START{$data}) <= $length_contig) { 
                if (($QUERY_START{$data} - 1 + $HSP_LENGTH{$data}) == ($QUERY_LENGTH{$data} + $no_gaps_gene)){
                  $variant = "9a";
                  $sub_contig = substr($contig, ($HIT_START{$data}-1),  ($QUERY_LENGTH{$data} + $no_gaps_gene - $no_gaps_hit));
                  $spaces_match_string = $QUERY_START{$data};
                }
                elsif (($QUERY_START{$data} + $HSP_LENGTH{$data}) < $QUERY_LENGTH{$data}){
                  $spaces_match_string = $QUERY_START{$data};
                  if ($HIT_START{$data} - ($QUERY_LENGTH{$data} - $HSP_LENGTH{$data} - $QUERY_START{$data}) < 0) {
                    $variant = "9b";
                    $major_variants_detector = 1;
                    $sub_contig = substr($contig, 0 , $HSP_LENGTH{$data} + $QUERY_START{$data} + $HIT_START{$data} - 2);
                  }
                  elsif ($HIT_START{$data} - ($QUERY_LENGTH{$data} - $HSP_LENGTH{$data} - $QUERY_START{$data}) >= 0) {
                    $variant = "9c";
                    $sub_contig = substr($contig, ($HIT_START{$data} -2 - ($QUERY_LENGTH{$data} - $HSP_LENGTH{$data} - $QUERY_START{$data} )),  $QUERY_LENGTH{$data});
                  }
                }
              }
            }
            else {    
              #print "New option not taken into account!\n";       
            }
            
            $sub_rev_contig = reverse($sub_contig);
            $sub_rev_contig =~ tr/acgt/tgca/;
            $sub_contig = $sub_rev_contig;
          } # End elsif ($HIT_STRAND{$data} == -1){
        } # End for (@{ $Seqs_genome_ref }) {
        
        #Adding gaps to the sub_contig (if there are any) leading to the creation of final_contig
        if ($no_gaps_hit > 0){
          my $hsp_length1 = (length $sub_contig) + $no_gaps_hit;
          my $sign1;
          my $flag1 = 0;
          my $start1 = 0;
          for (my $i = 0 ; $i < $hsp_length1 ; ++$i){
            #print "i: $i\n";
            $flag1 = 0;
            foreach my $pos (@gaps_in_hit){
              #print "pos: $pos\n";
              #print "Hit start:  $HIT_START{$allele}\n";
              if ($variant != 4){
                if ($i == ($pos + $QUERY_START{$data} -1)){
                 $sign1 = "-";
                 $flag1 = 1;
                 $start1 = $start1 - 1;
                }
              }
              else {
                if ($i == ($pos + $HIT_START{$data} -1)){
                  #print "\nWe enter this if\n";
                  $sign1 = "-";
                  $flag1 = 1;
                  $start1 = $start1 - 1;
                }
              }
            }
            unless ($flag1 == 1) {
              $sign1 = substr($sub_contig, $start1 , 1);
            }
            $final_contig .= $sign1;
            ++$start1;
          } #END for (my $i = 0 ; $i < $hsp_length1 ; ++$i){
        } #END if ($no_gaps_hit > 0){
        else {
          $final_contig = $sub_contig;
        }
        #print "####\n final hit contig: $final_contig\n ##################";   
        #Adding gaps to the mlst allele sequence, $seq_lower_case (if there are any) leading to the creation of final_seq_lower_case
        if ($no_gaps_gene > 0){
          my $hsp_length2 = (length $seq_lower_case) + $no_gaps_gene;
          my $sign2;
          my $flag2 = 0;
          my $start2 = 0;
          for (my $i = 0 ; $i < $hsp_length2 ; ++$i){
            $flag2 = 0;
            foreach my $pos (@gaps_in_gene){
              if ($i == ($pos + $QUERY_START{$data} -1)){
                $sign2 = "-";
                $flag2 = 1;
                $start2 = $start2 - 1;
              }
            }
            unless ($flag2 == 1) {
              $sign2 = substr($seq_lower_case, $start2 , 1);
            }
            $final_seq_lower_case .= $sign2;
            ++$start2;
          }
        }   
        else {
          $final_seq_lower_case = $seq_lower_case;
        } 
      } 
      else { #If length !=
        push(@{$GENE_RESULTS_HASH{$gene}}, "warning2");
        push(@{$GENE_RESULTS_HASH2{$gene}}, "warning2");
        #print "Warning2 - $gene\n";
        my $notes_1;
        if (exists $Notes_hash{$note}){
          $notes_1 = $Notes_hash{$note};
        } #End if (exists $Pheno_hash{$gene})
        push(@{$GENE_RESULTS_HASH{$gene}},sprintf("%.2f", $PERC_IDENT{$data})); #% ID
        push(@{$GENE_RESULTS_HASH{$gene}}, $QUERY_LENGTH{$data}); # Query lenght
        push(@{$GENE_RESULTS_HASH{$gene}}, $HSP_LENGTH{$data}); # HSP langht
        push(@{$GENE_RESULTS_HASH{$gene}}, $CONTIG_NAME{$data}); # Name of Contig
        push(@{$GENE_RESULTS_HASH{$gene}}, $position); # Start..END position in contig
        push(@{$GENE_RESULTS_HASH{$gene}}, $GENEID{$gene}); # e.g. tet(A)_2_AC12345
        push(@{$GENE_RESULTS_HASH{$gene}}, $notes_1); #Phenotype
        push(@{$GENE_RESULTS_HASH{$gene}}, $accNR); #Accession number
        push(@{$GENE_RESULTS_HASH{$gene}}, $genename); # Genename, e.g. tet(A)
        $seq_lower_case = $Q_STRING{$data}; #for printing alignment
        $final_contig = $HIT_STRING{$data}; #for printing alignment
        # For alignment
        push(@{$GENE_RESULTS_HASH2{$gene}},sprintf("%.2f", $PERC_IDENT{$data})); #% ID
        push(@{$GENE_RESULTS_HASH2{$gene}}, $QUERY_LENGTH{$data}); # Query lenght
        push(@{$GENE_RESULTS_HASH2{$gene}}, $HSP_LENGTH{$data}); # HSP langht
        push(@{$GENE_RESULTS_HASH2{$gene}}, $CONTIG_NAME{$data}); # Name of Contig
        push(@{$GENE_RESULTS_HASH2{$gene}}, $position); # Start..END position in contig
        push(@{$GENE_RESULTS_HASH2{$gene}}, $QUERY_START{$data}); #
        push(@{$GENE_RESULTS_HASH2{$gene}}, $genename); # Genename, e.g. tet(A)

                #Identifying gaps in the MLST allele string and hit string
        @gaps_in_gene = Getting_gaps($Q_STRING{$data});
        @gaps_in_hit = Getting_gaps($HIT_STRING{$data});
        #foreach my $elem (@gaps_in_hit){
        #print "####\n$elem\n#####";
        #}
    
        $no_gaps_gene = scalar @gaps_in_gene;
        $no_gaps_hit = scalar @gaps_in_hit;

        #Getting the complete mlst allele (even thought it may not all be part of the HSP)   
        my @array_for_getting_mlst_seq = ($GENEID{$data});
        my $Seqs_ref = grep_ids(-seqs => $Seqs_ABres, -ids => \@array_for_getting_mlst_seq);  
        for (@{ $Seqs_ref }) {
          $seq_lower_case = lc($_->seq);
        }
    
        #Getting the right contig
        my @array_for_getting_genome_seq = ($CONTIG_NAME{$data});
        my $Seqs_genome_ref = grep_ids(-seqs => $Seqs_input, -ids => \@array_for_getting_genome_seq);  
        for (@{ $Seqs_genome_ref }) {
          my $contig = lc($_->seq);
          my $length_contig = length($contig);  #Redundant, da jeg også v.h.a. bioperl finder hit length
       
          #Getting the right sub_contig depends on which strand the hit is on
          #If the hit is on the +1 
          if ($HIT_STRAND{$data} == 1){
            if (($QUERY_START{$data} == 1) && (($QUERY_LENGTH{$data} + $no_gaps_gene) == $HSP_LENGTH{$data})){  
              $variant = 1;
              $sub_contig = substr($contig, ($HIT_START{$data} - 1 ),  ($HSP_LENGTH{$data} - $no_gaps_hit) );
            }
            elsif (($QUERY_START{$data} == 1) && (($QUERY_LENGTH{$data} + $no_gaps_gene) > $HSP_LENGTH{$data})) { 
              if (($HIT_START{$data} + ($QUERY_LENGTH{$data} + $no_gaps_gene)) > ($length_contig + $no_gaps_hit)){ 
                $variant = 2;
                $major_variants_detector = 1;
                $sub_contig = substr($contig, ($HIT_START{$data} - 1 ),  $HSP_LENGTH{$data});
              }
              elsif (($HIT_START{$data} + ($QUERY_LENGTH{$data} + $no_gaps_gene)) <= ($length_contig + $no_gaps_hit)) {
                $variant = 3;
                $sub_contig = substr($contig, ($HIT_START{$data} - 1 ),  ($QUERY_LENGTH{$data} + $no_gaps_gene - $no_gaps_hit));
              }
            }
            elsif ($QUERY_START{$data} > 1){
              if (($HIT_START{$data} - $QUERY_START{$data}) < 0){
                $variant = 4;
                $major_variants_detector = 1;
                $sub_contig = substr($contig, 0,  ( $HIT_START{$data} + (($QUERY_LENGTH{$data} + $no_gaps_gene) - $QUERY_START{$data})));
                #If, as here, the HSP only starts some nucleotides within the mlst allele, a number of spaces must be written before the matching string from the genome. Likewise, the match-string (the "|| ||| ||") should be preceeded by spaces
                $spaces_hit = $QUERY_START{$data} - $HIT_START{$data} + 1;
                $spaces_match_string = $QUERY_START{$data};
              }
              else {    
                if ((($HIT_START{$data} - $QUERY_START{$data}) + ($QUERY_LENGTH{$data} + $no_gaps_gene)) < ($HIT_LENGTH{$data} + $no_gaps_hit)){
                  $variant = "5a";
                  $sub_contig = substr($contig, ($HIT_START{$data} - $QUERY_START{$data}), ($QUERY_LENGTH{$data} + $no_gaps_gene));
                  $spaces_match_string = $QUERY_START{$data};
                }
                else {
                  $variant = "5b";
                  $major_variants_detector = 1;
                  $sub_contig = substr($contig, ($HIT_START{$data} - $QUERY_START{$data}),  ((($HIT_LENGTH{$data} + $no_gaps_hit) - $HIT_START{$data}) + $QUERY_START{$data} -1 ));
                  $spaces_match_string = $QUERY_START{$data};
                }
              }
            }
            else {
              #print "New option not taken into account!\n";
            }
          } 
       
          #If the hit is on the -1 strand
          elsif ($HIT_STRAND{$data} == -1){
            if (($QUERY_START{$data} == 1) && (($QUERY_LENGTH{$data} + $no_gaps_gene) == $HSP_LENGTH{$data})){
              $variant = 6;
              $sub_contig = substr($contig, ($HIT_START{$data} - 1 ), ($HSP_LENGTH{$data} - $no_gaps_hit));
            }
            elsif (($QUERY_START{$data} == 1) && (($QUERY_LENGTH{$data} + $no_gaps_gene ) > $HSP_LENGTH{$data})) {
              if(($HIT_START{$data}-(($QUERY_LENGTH{$data} + $no_gaps_gene) - ($HSP_LENGTH{$data} - $no_gaps_hit))) >= 0){
                $variant = 7;
                $sub_contig = substr($contig, ($HIT_START{$data}-(($QUERY_LENGTH{$data} + $no_gaps_gene) - ($HSP_LENGTH{$data} - $no_gaps_hit))) - 1,  (($QUERY_LENGTH{$data} + $no_gaps_gene )));
              }
              elsif (($HIT_START{$data}-(($QUERY_LENGTH{$data} + $no_gaps_gene ) - ($HSP_LENGTH{$data} - $no_gaps_hit))) < 0){
                $variant = 8;
                $major_variants_detector = 1;
                $sub_contig = substr($contig, 0 , ($HIT_START{$data} + ($HSP_LENGTH{$data}- $no_gaps_hit) -1));
              }
            }
            elsif ($QUERY_START{$data} > 1){
              if (($HIT_START{$data} + $QUERY_LENGTH{$data}) > $length_contig){ 
                #If, as here, the HSP only starts some nucleotides within the mlst allele, a number of spaces must be written before the matching string from the genome
                $variant = 10;
                $major_variants_detector = 1;
                $spaces_hit = $QUERY_START{$data} - ($length_contig - $HIT_END{$data}) ;
                $spaces_match_string = $QUERY_START{$data};
                $sub_contig = substr($contig, ($HIT_START{$data} -1 - ($QUERY_LENGTH{$data} - $HSP_LENGTH{$data} - $QUERY_START{$data}+1)), ((($QUERY_LENGTH{$data} - $QUERY_START{$data})+($length_contig - $HIT_END{$data}))+1));
              }
              elsif (($HIT_START{$data} + $QUERY_START{$data}) <= $length_contig) { 
                if (($QUERY_START{$data} - 1 + $HSP_LENGTH{$data}) == ($QUERY_LENGTH{$data} + $no_gaps_gene)){
                  $variant = "9a";
                  $sub_contig = substr($contig, ($HIT_START{$data}-1),  ($QUERY_LENGTH{$data} + $no_gaps_gene - $no_gaps_hit));
                  $spaces_match_string = $QUERY_START{$data};
                }
                elsif (($QUERY_START{$data} + $HSP_LENGTH{$data}) < $QUERY_LENGTH{$data}){
                  $spaces_match_string = $QUERY_START{$data};
                  if ($HIT_START{$data} - ($QUERY_LENGTH{$data} - $HSP_LENGTH{$data} - $QUERY_START{$data}) < 0) {
                    $variant = "9b";
                    $major_variants_detector = 1;
                    $sub_contig = substr($contig, 0 , $HSP_LENGTH{$data} + $QUERY_START{$data} + $HIT_START{$data} - 2);
                  }
                  elsif ($HIT_START{$data} - ($QUERY_LENGTH{$data} - $HSP_LENGTH{$data} - $QUERY_START{$data}) >= 0) {
                    $variant = "9c";
                    $sub_contig = substr($contig, ($HIT_START{$data} -2 - ($QUERY_LENGTH{$data} - $HSP_LENGTH{$data} - $QUERY_START{$data} )),  $QUERY_LENGTH{$data});
                  }
                }
              }
            }
            else {    
              #print "New option not taken into account!\n";       
            }
            
            $sub_rev_contig = reverse($sub_contig);
            $sub_rev_contig =~ tr/acgt/tgca/;
            $sub_contig = $sub_rev_contig;
          } # End elsif ($HIT_STRAND{$data} == -1){
        } # End for (@{ $Seqs_genome_ref }) {
        
        #Adding gaps to the sub_contig (if there are any) leading to the creation of final_contig
        if ($no_gaps_hit > 0){
          my $hsp_length1 = (length $sub_contig) + $no_gaps_hit;
          my $sign1;
          my $flag1 = 0;
          my $start1 = 0;
          for (my $i = 0 ; $i < $hsp_length1 ; ++$i){
            #print "i: $i\n";
            $flag1 = 0;
            foreach my $pos (@gaps_in_hit){
              #print "pos: $pos\n";
              #print "Hit start:  $HIT_START{$allele}\n";
              if ($variant != 4){
                if ($i == ($pos + $QUERY_START{$data} -1)){
                 $sign1 = "-";
                 $flag1 = 1;
                 $start1 = $start1 - 1;
                }
              }
              else {
                if ($i == ($pos + $HIT_START{$data} -1)){
                  #print "\nWe enter this if\n";
                  $sign1 = "-";
                  $flag1 = 1;
                  $start1 = $start1 - 1;
                }
              }
            }
            unless ($flag1 == 1) {
              $sign1 = substr($sub_contig, $start1 , 1);
            }
            $final_contig .= $sign1;
            ++$start1;
          } #END for (my $i = 0 ; $i < $hsp_length1 ; ++$i){
        } #END if ($no_gaps_hit > 0){
        else {
          $final_contig = $sub_contig;
        }
        #print "####\n final hit contig: $final_contig\n ##################";   
        #Adding gaps to the mlst allele sequence, $seq_lower_case (if there are any) leading to the creation of final_seq_lower_case
        if ($no_gaps_gene > 0){
          my $hsp_length2 = (length $seq_lower_case) + $no_gaps_gene;
          my $sign2;
          my $flag2 = 0;
          my $start2 = 0;
          for (my $i = 0 ; $i < $hsp_length2 ; ++$i){
            $flag2 = 0;
            foreach my $pos (@gaps_in_gene){
              if ($i == ($pos + $QUERY_START{$data} -1)){
                $sign2 = "-";
                $flag2 = 1;
                $start2 = $start2 - 1;
              }
            }
            unless ($flag2 == 1) {
              $sign2 = substr($seq_lower_case, $start2 , 1);
            }
            $final_seq_lower_case .= $sign2;
            ++$start2;
          }
        }   
        else {
          $final_seq_lower_case = $seq_lower_case;
        } 

      }# End else# End else
      #Nicely printing the sequences
      # print contig_name
      #print "Con: $CONTIG_NAME{$data}, HSP: $HSP_LENGTH{$data}, Acc: $accNR, Pos: $position\n";
      #push(@{$GENE_ALIGN_HIT_HASH{$gene}}, $CONTIG_NAME{$data});
      for (my $j = 0 ; $j < $QUERY_LENGTH{$data} ; $j+=60){
        #Printing the resistance gene
        #print "Resistance gene:   ";
        my $ABres_substr = substr($final_seq_lower_case, $j , 60);
        #print $ABres_substr . "\n";
        push(@{$GENE_ALIGN_QUERY_HASH{$gene}}, $ABres_substr);
   
        #Printing spaces before the match string with the "|| |||| || ||" and the string itself
        #print "                   ";
        my $string_spaces = "";  #For saving the spaces as a string of spaces instead of a number of spaces
        for (my $i = 1 ; $i < $spaces_match_string; ++$i){
          $string_spaces .= " ";  
        }
        my $homo_string =  $string_spaces . $HOMO_STRING{$data};
        my $homo_string_substr = substr($homo_string, $j , 60);
        #print $homo_string_substr . "\n";
        push(@{$GENE_ALIGN_HOMO_HASH{$gene}}, $homo_string_substr);
   
        #Printing the match in the genome
        my $string_spaces_hit = "";  #For saving the spaces as a string of spaces instead of a number of spaces
        for (my $i = 1 ; $i < $spaces_hit ; ++$i){
          $string_spaces_hit .= " ";  
        }
        #@#print "Hit in genome:   ";
        #print "Hit in genome:     ";
        my $string_final_contig = $string_spaces_hit . $final_contig;
        my $string_final_contig_substr = substr($string_final_contig, $j , 60);
        #print $string_final_contig_substr . "\n\n";
        push(@{$GENE_ALIGN_HIT_HASH{$gene}}, $string_final_contig_substr);
      }# for (my $j = 0 ; $j < $QUERY_LENGTH{$data} ; $j+=60){
    } else {# End if ($HSP_LENGTH{$data} >= (1/5)*$QUERY_LENGTH{$data} and $PERC_IDENT{$data} >= $threshold) {
      # Remove $gene from hash
      delete $GENE_RESULTS_HASH{$gene};
    }
 
  } # End foreach my $gene (keys %Profile){

  my $length = scalar@control;
  push(@RESULTS_AND_SETTINGS_ARRAY, $length);
  push(@RESULTS_AND_SETTINGS_ARRAY, $argfProfiles{$element});
  push(@RESULTS_AND_SETTINGS_ARRAY, $InFile);
  push(@RESULTS_AND_SETTINGS_ARRAY, $threshold);
  
   ## Making a hash with results for txt printing WORKS
  foreach my $key (sort keys %GENE_RESULTS_HASH) {
    my $array = $GENE_RESULTS_HASH{$key};   
    $FINAL_RESULTS{$key}= [@$array[9], @$array[1], @$array[2], @$array[3],  @$array[4], @$array[5], @$array[8], $CurrentAnti];
    my @tmp = split(/\<br\>/, @$array[7]);
    my $function = $tmp[0] ;
    $Virulencetable .= @$array[9]."\t\t".$function."\n";
    $Virulencetable .= "-----------\n";
    $tabr .= @$array[9]."\t".@$array[1]."\t".@$array[3]."/".@$array[2]."\t".@$array[4]."\t".@$array[5]."\t".$function."\t".@$array[8]."\n";
    
  } 
} # End foreach my $element(@Antimicrobial){

my $contigcount = 0; ## To give the contig numbers and put the real contig names in a table
### Print FINAL_RESULT WORKS 
foreach my $key (sort keys %FINAL_RESULTS) {
  $contigcount ++;
  my $array = $FINAL_RESULTS{$key};
  my $header = ucfirst @$array[7];
  $txtresults .="*********************************************************************************\n";
  $txtresults .= $header."\n" ;
  $txtresults .="*********************************************************************************\n";
  $txtresults .="VIRULENCE FACTOR  IDENTITY  QUERY/HSP     CONTIG  POSITION         ACC NO.       \n";
  $txtresults .="=================================================================================\n";
  my $spaceno = (length($headarray[0]) - length(@$array[0]));
  my $spaceno1 = (length($headarray[1]) - length(@$array[1]));
  my $spaceno2 = (length($headarray[2]) - (length(@$array[2])+length(@$array[3])+1));
  my $spaceno3 = (length($headarray[3]) - length($contigcount));
  my $spaceno4 = (length($headarray[4]) - length(@$array[5]));
  my $spaceno5 = (length($headarray[5]) - length(@$array[6]));
  my $spacestr = " " x $spaceno;  #(length @headarray[0] - length @$array[0]);
  my $spacestr1 = " " x $spaceno1;
  my $spacestr2 = " " x $spaceno2;
  my $spacestr3 = " " x $spaceno3;
  my $spacestr4 = " " x $spaceno4;
  my $spacestr5 = " " x $spaceno5; 
  $txtresults .= @$array[0].$spacestr.@$array[1].$spacestr1.@$array[3]."/".@$array[2].$spacestr2.$contigcount.$spacestr3.@$array[5].$spacestr4.@$array[6].$spacestr5."\n";
  $txtresults .="_________________________________________________________________________________\n\n";
  $contigtable .= "Contig ".$contigcount." is ".@$array[4]."\n";
  $contigtable .= "-----------\n";
}

## Printing the alignments as text, making a txt string with alignment
  
foreach my $key (sort keys %GENE_RESULTS_HASH2) {
  	# print header line for each gene
	  
  my $array = $GENE_RESULTS_HASH2{$key}; 
  my $outStr = @$array[7];
    #my $matchAll = lc(@$array[5]);
  if (@$array[0] eq "perfect" ){
	 $outStr .= ": PERFECT MATCH, "; 
  }
  elsif (@$array[0] eq "warning1"){
    $outStr = $outStr.": WARNING1, "; 
  }
  elsif (@$array[0] eq "warning2"){
    $outStr = $outStr.": WARNING2, "; 
  }  
  $alignment .= $outStr."ID: ".@$array[1]."%, Query/HSP Length: ".@$array[3]."/".@$array[2]. ", Contig name: ".@$array[4].", Position: ".@$array[5]."\n\n";
  $hits_in_seq .= ">".$outStr."ID: ".@$array[1]."%, Query/HSP Length: ".@$array[3]."/".@$array[2]. ", Contig name: ".@$array[4].", Position: ".@$array[5]."\n"; #måske forkert text
  $resalign .= ">".@$array[7]."\n";

	 #now print the alleles
  my $queryArray = $GENE_ALIGN_QUERY_HASH{$key};
  my $homoArray = $GENE_ALIGN_HOMO_HASH{$key};
  my $hitArray = $GENE_ALIGN_HIT_HASH{$key};
	
  for (my $i=0; $i < scalar(@$hitArray); $i++){
	 my $tmpQuerySingleLine = @$queryArray[$i];
	 my $tmpHomoSingleLine = @$homoArray[$i];
	 my $tmpHitSingleLine = @$hitArray[$i];

	 $alignment .= "Virulence gene seq:  ".$tmpQuerySingleLine."\n";
	 $alignment .= "                     ".$tmpHomoSingleLine."\n";
	 $alignment .= "Hit in genome:       ".$tmpHitSingleLine."\n\n";
	 $resalign .= $tmpQuerySingleLine."\n";
	 $hits_in_seq .= $tmpHitSingleLine."\n";
  }#end for
  $alignment .= "\n--------------------------------------------------------------------------------\n\n";
}#end foreach
  
		#WRITING standard_output.txt
open (TXTRESULTS, '>>',"$dir/results.txt") or die("Error! Could not write to results.txt");
print TXTRESULTS $txtresults;
print TXTRESULTS $contigtable;
print TXTRESULTS $Virulencetable;
print TXTRESULTS $alignment;
close (TXTRESULTS);
#print $txtresults; #printing to screen	

open (TABR, '>'."$dir/results_tab.txt") || die("Error! Could not write to Hit_in_genome_seq.fsa");
print TABR $tabr;
close (TABR);


	#WRITING Hit_in_genome_seq.fsa
open (HIT, '>'."$dir/Hit_in_genome_seq.fsa") || die("Error! Could not write to Hit_in_genome_seq.fsa");
print HIT $hits_in_seq;
close (HIT);

#WRITING Virulence_gene_seq.fsa
open (ALLELE, '>'."$dir/Virulence_gene_seq.fsa") || die("Error! Could not write to Virulence_gene_seq.fsa");
print ALLELE $resalign;
close (ALLELE);

print STDERR "Done\n";
exit;



# --------------------------------------------------------------------
# %% Land of the Subroutines %%

sub commandline_parsing {
    while (scalar @ARGV) {
        if ($ARGV[0] =~ m/^-d$/) {
            $ABRES_DB = $ARGV[1];
            $Notes1 = "$ABRES_DB/notes.txt";
            shift @ARGV;
            shift @ARGV;
        }
        elsif ($ARGV[0] =~ m/^-b$/) {
            $BLAST = $ARGV[1];
			$BLASTALL = "$BLAST/bin/blastall";
            $FORMATDB = "$BLAST/bin/formatdb";
            shift @ARGV;
            shift @ARGV;
        }
		elsif ($ARGV[0] =~ m/^-k$/) {
            $threshold = $ARGV[1];
            shift @ARGV;
            shift @ARGV;
        }
        elsif ($ARGV[0] =~ m/^-s$/) {
            $AB_input = $ARGV[1];
            shift @ARGV;
            shift @ARGV;
        }
        elsif ($ARGV[0] =~ m/^-i$/) {
            $InFile = $ARGV[1];
            shift @ARGV;
            shift @ARGV;
        }
        elsif ($ARGV[0] =~ m/^-o$/) {
            $dir = $ARGV[1];
            mkdir $dir;
            shift @ARGV;
            shift @ARGV;
        }
        elsif ($ARGV[0] =~ m/^-h$/) {
            $Help = 1;
            shift @ARGV;
        }
        else {
         &print_help();
         exit
        }
    }
}

############# Phenotype sub ########
# Making hash of phenotypes, genename = phenotype.

sub phenolist {
  my ($filename) = @_;
  my %hash;
  open(IN, '<', $filename) or die "Error: $!\n";
  while (defined(my $line = <IN>)) {
    my @tmp = split(/:/, $line);
    $hash{$tmp[0]} = "$tmp[1]<br>$tmp[2]";
  }
  close IN;
  return %hash;
}

###################################
# Run blast and parse output
# Arguments should be a hash with arguments to blast in option => value format
# Returns text lines of blast output

sub get_blast_run {
  my %args        = @_;
  my ($fh, $file) = tempfile( DIR => '/tmp', UNLINK => 1); 
  #print "\ntemp filename: $file\n";
  output_sequence(-fh => $fh, seqs => delete $args{-d}, -format => 'fasta');
  die "Error! Could not build blast database" if (system("$FORMATDB -p F -i $file")); 
  my $query_file = $file.".blastpipe";

  open QUERY, ">> $query_file" || die("Error! Could not perform blast run");
  output_sequence(-fh => \*QUERY, seqs => $args{-i}, -format => 'fasta');
  close QUERY;

  delete $args{-i};
  my $cmd = join(" ", %args);
  my ($fh2, $file2) = tempfile( DIR => '/tmp', UNLINK => 1); 
  #print "\ntemp filename: $file2\n";
  print $fh2 `$BLASTALL -d $file -i $query_file $cmd`;
  close $fh2;
  #system("$BLASTALL -d $file -i $query_file $cmd > $file2");
  #system ("echo -d $file -i $query_file $cmd ");
  my $report = new Bio::SearchIO(
         -file => $file2,
              -format => "blast"); 
# Go through BLAST reports one by one, evt. array in array...              
my @blast;
while(my $result = $report->next_result) {
   # Go through each matching sequence
   while(my $hit = $result->next_hit)    { 
      # Go through each HSP for this sequence
        while (my$hsp = $hit->next_hsp)  { 
            push(@blast, 
      $result->query_accession . "\t" . 
      $result->query_length . "\t" . 
      $hsp->hsp_length . "\t" . 
      $hsp->gaps . "\t" . 
      $hsp->percent_identity .  "\t" .  
      $hsp->evalue . "\t" . 
      $hsp->bits . "\t" . 
      $hsp->query_string ."\t" . 
      $hsp->hit_string ."\t" . 
      $hsp->homology_string . "\t" . 
      $hsp->seq_inds . "\t" .
      $hsp->strand('hit') . "\t" .
      $hsp->start('hit') . "\t" .
      $hsp->end('hit') . "\t" .
      $hit->name . "\t" .
      $hsp->strand('query') . "\t" .
      $hsp->start('query') . "\n");
      } 
   } 
}
unlink 'formatdb.log', 'error.log', "$file.blastpipe" , "$file.nhr" , "$file.nin" , "$file.nsq";
#system("rm -rf formatdb.log error.log");
return @blast;
}

###################################
# Finds sequences with specific ids in an array of Bio::Seq objects
# Args:
#   -seqs => A reference to an array with Bio::Seq objects
#   -ids  => A reference to an array of ids
#   -v    => Like for grep, if defined, return the ids which didn't match
# Returns
#   An array (or array reference) with the Bio::Seq objects having the requested ids

sub grep_ids {
  my %argv = @_;
  my %ids;
  for my $id (@{ $argv{-ids} }) {
    $ids{$id} = 1;
  }
  my @out;
  for my $seq (@{ $argv{-seqs} }) {
    if (exists $ids{$seq->id()}) {
      push @out, $seq unless (defined $argv{-v});
    } elsif (defined $argv{-v}) {
      push @out, $seq;
    }
  }
  return wantarray ? @out : \@out;
}

###################################
# Reads one sequence file in a format supported by BioPerl
# Arguments should be an array:
#   Filenames to be loaded, ideally the @ARGV array
#   -fh         => The filehandle to read from, defaults to ARGV
#   -format     => The file format, defaults to "fasta"
#   <...>       => Additional options to Bio::SeqIO
# Returns:
#   A reference to an array of Bio::Seq objects

sub read_seqs {
  my %args      = @_;
  $args{-fh}    = \*ARGV unless (exists $args{-fh} or exists $args{-file});
  my (@seqs, %ids);
  $args{-format} = "fasta" unless (defined $args{-format});
  my $seq_in = Bio::SeqIO->new(%args);
  while (my $seq = $seq_in->next_seq) {
    push @seqs, $seq;
  }
  return (wantarray ? @seqs : \@seqs);
}

#####################################
#This sub takes a nucleotide string as input and identifies gaps ("-").
#An array with positions of the gaps is returned
sub Getting_gaps {
  my $input_string = $_[0];
  my @split_input_string = split('',$input_string);
  my @gap_positions;
  for (my $i = 0 ; $i < (scalar @split_input_string) ; ++$i){
    if ($split_input_string[$i] eq "-"){
      push(@gap_positions,$i);
    }
  }
  
  return (@gap_positions);
}

###################################
# Output in sequence formats supported by bioperl
# Arguments should be a hash:
#   seqs    => A reference to an array of sequences. Values are ids or Bio::Seq objects
#   tempdir => If set, writes to a temp file in specified directory instead. Uses File::Temp
#   Any additional arguments will be forwarded to the Bio::SeqIO->new() call.
#      If these don't include either -fh or -file, STDOUT will be used (but see tempdir)
# Returns:
#   The filehandle and filename

sub output_sequence {
  my %args = @_;
  my $seqs_ref = delete $args{seqs};
  my $i = 1;
  $args{-fh} = \*STDOUT unless (exists $args{-fh} or exists $args{-file});
  if (exists $args{tempdir}) {
    my $tempdir = delete $args{tempdir};
    ($args{-fh}, $args{-file}) = tempfile(DIR => $tempdir, SUFFIX => ".".$args{-format})
  }
  my $file = delete $args{-file} if (exists $args{-fh} && exists $args{-file}); # Stupid BioPerl cannot handle that both might be set...
  my $seq_out = Bio::SeqIO->new(%args);
  $args{-file} = $file if (defined $file);
  for my $seq (@{ $seqs_ref }) {
    $seq_out->write_seq($seq);
  }
  return ($args{-fh}, $args{-file});
}

# --------------------------------------------------------------------
# %% Help Page/Documentation %%
#

sub print_help {
  my $ProgName     = PROGRAM_NAME;
  my $ProgNameLong = PROGRAM_NAME_LONG;
  my $Version      = VERSION;
  my $CMD = join(" ", %ARGV);
  print <<EOH;

NAME
  $ProgName - $ProgNameLong

SYNOPSIS
  $ProgName [Options]

DESCRIPTION
  VirulenceFinder identifies viruelnce genes in total or partial sequenced
  isolates of bacteria - at the moment only E. coli, Enterococcus and S. aureus are available.
  
  Notice also that the default options for BLAST are changed to suit the
  VirulenceFinder alignment.

OPTIONS

	-h HELP
                    Prints a message with options and information to the screen
    -d DATABASE
                    The path to where you have located the database folder
    -b BLAST
                    The path to the location of blast-2.2.26 if it is not added
                    to the user's path (see the install guide in 'README.md') 
    -i INFILE
                    Your input file which needs to be preassembled partial
                    or complete genomes in fasta format
    -o OUTFOLDER
                    The folder you want to have your output files stored.
                    If not specified the program will create a folder named
                    'Output' in which the result files will be stored
    -s SCHEMES
                    The schemes. You can find an overview of the schemes in the
                    config file. Separate multiple database prefixes with comma
    -k THRESHOLD
                    The threshold for % identity for example '95.00' for 95 %

Example of use with the 'database' folder located in the current directory and Blast added to the user's path
    
    perl VirulenceFinder-1.4.pl -i test.fsa -o OUTFOLDER -s virulence_ecoli -k 95.00

Example of use with the 'database' and 'blast-2.2.26' folders loacted in other directories

    perl VirulenceFinder-1.4.pl -d path/to/database -b path/to/blast-2.2.26 -i test.fsa -o OUTFOLDER -s virulence_ecoli -k 95.00
    

VERSION
    Current: $Version

AUTHORS
    Carsten Friis, carsten\@cbs.dtu.dk, Mette Voldby Larsen, metteb\@cbs.dtu.dk, Ea Stilling

EOH
}