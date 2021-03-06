package TTF::Cmap;

=head1 NAME

TTF::Cmap - Character map table

=head1 DESCRIPTION

Looks after the character map. The primary structure used for handling a cmap
is the L<TTF::Segarr> which handles the segmented arrays of format 4 tables,
and in a simpler form for format 0 tables.

Due to the complexity of working with segmented arrays, most of the handling of
such arrays is via methods rather than via instance variables.

One important feature of a format 4 table is that it always contains a segment
with a final address of 0xFFFF. If you are creating a table from scratch this is
important (although L<TTF::Segarr> can work quite happily without it).


=head1 INSTANCE VARIABLES

The instance variables listed here are not preceeded by a space due to their
emulating structural information in the font.

=over 4

=item Num

Number of subtables in this table

=item Tables

An array of subtables ([0..Num-1])

=back

Each subtables also has its own instance variables which are, again, not
preceeded by a space.

=over 4

=item Platform

The platform number for this subtable

=item Encoding

The encoding number for this subtable

=item Format

Gives the stored format of this subtable

=item Ver

Gives the version (or language) information for this subtable

=item val

This points to a L<TTF::Segarr> which contains the content of the particular
subtable.

=back

=head1 METHODS

=cut

use strict;
use vars qw(@ISA);
require TTF::Table;
require TTF::Segarr;

@ISA = qw(TTF::Table);


=head2 $t->read

Reads the cmap into memory. Format 4 subtables read the whole subtable and
fill in the segmented array accordingly.

Format 2 subtables are not read at all.

=cut

sub read
{
    my ($self) = @_;
    my ($dat, $i, $j, $k, $id, @ids, $s);
    my ($start, $end, $range, $delta, $form, $len, $num, $ver);
    my ($fh) = $self->{' INFILE'};

    $self->SUPER::read or return $self;
    read($fh, $dat, 4);
    $self->{'Num'} = unpack("x2n", $dat);
    $self->{'Tables'} = [];
    for ($i = 0; $i < $self->{'Num'}; $i++)
    {
        $s = {};
        read($fh, $dat, 8);
        ($s->{'Platform'}, $s->{'Encoding'}, $s->{'LOC'}) = (unpack("nnN", $dat));
        $s->{'LOC'} += $self->{' OFFSET'};
        push(@{$self->{'Tables'}}, $s);
    }
    for ($i = 0; $i < $self->{'Num'}; $i++)
    {
        $s = $self->{'Tables'}[$i];
        seek($fh, $s->{'LOC'}, 0);
        read($fh, $dat, 6);
        ($form, $len, $ver) = (unpack("n3", $dat));

        $s->{'Format'} = $form;
        $s->{'Ver'} = $ver;
        if ($form == 0)
        {
            $s->{'val'} = TTF::Segarr->new;
            read($fh, $dat, 256);
            $s->{'val'}->fastadd_segment(0, 2, unpack("C*", $dat));
            $s->{'Start'} = 0;
            $s->{'Num'} = 256;
        } elsif ($form == 6)
        {
            my ($start, $ecount);
            
            read($fh, $dat, 4);
            ($start, $ecount) = unpack("n2", $dat);
            read($fh, $dat, $ecount << 1);
            $s->{'val'} = TTF::Segarr->new;
            $s->{'val'}->fastadd_segment($start, 2, unpack("n*", $dat));
            $s->{'Start'} = $start;
            $s->{'Num'} = $ecount;
        } elsif ($form == 2)
        {
# no idea what to do here yet
        } elsif ($form == 4)
        {
            read($fh, $dat, 8);
            $num = unpack("n", $dat);
            $num >>= 1;
            read($fh, $dat, $len - 14);
            $s->{'val'} = TTF::Segarr->new;
            for ($j = 0; $j < $num; $j++)
            {
                $end = unpack("n", substr($dat, $j << 1, 2));
                $start = unpack("n", substr($dat, ($j << 1) + ($num << 1) + 2, 2));
                $delta = unpack("n", substr($dat, ($j << 1) + ($num << 2) + 2, 2));
                $delta -= 65536 if $delta > 32767;
                $range = unpack("n", substr($dat, ($j << 1) + $num * 6 + 2, 2));
                @ids = ();
                for ($k = $start; $k <= $end; $k++)
                {
                    if ($range == 0)
                    { $id = $k + $delta; }
                    else
                    { $id = unpack("n", substr($dat, ($j << 1) + $num * 6 +
                                        2 + ($k - $start) * 2 + $range, 2)) + $delta; }
                    push (@ids, $id);
                }
                $s->{'val'}->fastadd_segment($start, 0, @ids);
            }
            $s->{'val'}->tidy;
            $s->{'Num'} = 0x10000;               # always ends here
            $s->{'Start'} = $s->{'val'}[0]{'START'};
        }
    }
    $self;
}


=head2 $t->ms_lookup($uni)

Given a Unicode value in the MS table (Platform 3, Encoding 1) locates that
table and looks up the appropriate glyph number from it.

=cut

sub ms_lookup
{
    my ($self, $uni) = @_;

    $self->find_ms || return undef unless (defined $self->{' mstable'});
    return $self->{' mstable'}{'val'}->at($uni);
}


=head2 $t->find_ms

Finds the Microsoft Unicode table and sets the C<mstable> instance variable
to it if found. Returns the table it finds.

=cut
sub find_ms
{
    my ($self) = @_;
    my ($i, $s, $alt);

    return $self->{' mstable'} if defined $self->{' mstable'};
    $self->read;
    for ($i = 0; $i < $self->{'Num'}; $i++)
    {
        $s = $self->{'Tables'}[$i];
        if ($s->{'Platform'} == 3)
        {
            if ($s->{'Encoding'} == 1)
            {
                $self->{' mstable'} = $s;
                last;
            } elsif ($s->{'Encoding'} == 0)
            { $alt = $s; }
        }
    }
    $self->{' mstable'} = $alt unless defined $self->{' mstable'};
    $self->{' mstable'};
}


=head2 $t->out($fh)

Writes out a cmap table to a filehandle. If it has not been read, then
just copies from input file to output

=cut

sub out
{
    my ($self, $fh) = @_;
    my ($loc, $s, $i, $base_loc, $j);

    return $self->SUPER::out($fh) unless $self->{' read'};

    $base_loc = tell($fh);
    print $fh pack("n2", 0, $self->{'Num'});

    for ($i = 0; $i < $self->{'Num'}; $i++)
    { print $fh pack("nnN", $self->{'Tables'}[$i]{'Platform'}, $self->{'Tables'}[$i]{'Encoding'}, 0); }
    
    for ($i = 0; $i < $self->{'Num'}; $i++)
    {
        $s = $self->{'Tables'}[$i];
        $s->{'val'}->tidy;
        $s->{' outloc'} = tell($fh);
        print $fh pack("n3", $s->{'Format'}, 0, $s->{'Ver'});       # come back for length
        if ($s->{'Format'} == 0)
        {
            print $fh pack("C256", $s->{'val'}->at(0, 256));
        } elsif ($s->{'Format'} == 6)
        {
            print $fh pack("n2", $s->{'Start'}, $s->{'Num'});
            print $fh pack("n*", $s->{'val'}->at($s->{'Start'}, $s->{'Num'}));
        } elsif ($s->{'Format'} == 2)
        {
        } elsif ($s->{'Format'} == 4)
        {
            my ($num, $sRange, $eSel);
            my (@deltas, $delta, @range, $flat, $k, $segs, $count);

            $num = $#{$s->{'val'}} + 1;
            $segs = $s->{'val'};
            for ($sRange = 1, $eSel = 0; $sRange <= $num; $eSel++)
            { $sRange <<= 1;}
            $eSel--;
            print $fh pack("n4", $num * 2, $sRange, $eSel, ($num * 2) - $sRange);
            print $fh pack("n*", map {$_->{'START'} + $_->{'LEN'} - 1} @$segs);
            print $fh pack("n", 0);
            print $fh pack("n*", map {$_->{'START'}} @$segs);

            for ($j = 0; $j < $num; $j++)
            {
                $delta = $segs->[$j]{'VAL'}[0]; $flat = 1;
                for ($k = 1; $k < $segs->[$j]{'LEN'}; $k++)
                {
                    if ($segs->[$j]{'VAL'}[$k] == 0)
                    { $flat = 0; }
                    if ($delta + $k != $segs->[$j]{'VAL'}[$k])
                    {
                        $delta = 0;
                        last;
                    }
                }
                push (@range, $flat);
                push (@deltas, ($delta ? $delta - $segs->[$j]{'START'} : 0));
            }
            print $fh pack("n*", @deltas);

            $count = 0;
            for ($j = 0; $j < $num; $j++)
            {
                $delta = $deltas[$j];
                if ($delta != 0 && $range[$j] == 1)
                { $range[$j] = 0; }
                else
                {
                    $range[$j] = ($count + $num - $j) << 1;
                    $count += $segs->[$j]{'LEN'};
                }
            }

            print $fh pack("n*", @range);

            for ($j = 0; $j < $num; $j++)
            {
                next if ($range[$j] == 0);
                for ($k = 0; $k < $segs->[$j]{'LEN'}; $k++)
                { print $fh pack("n", $segs->[$j]{'VAL'}[$k]); }
            }
        }

        $loc = tell($fh);
        seek($fh, $s->{' outloc'} + 2, 0);
        print $fh pack("n", $loc - $s->{' outloc'});
        seek($fh, $base_loc + 8 + ($i << 3), 0);
        print $fh pack("N", $s->{' outloc'} - $base_loc);
        seek($fh, $loc, 0);
    }
    $self;
}


=head2 @map = $t->reverse([$num])

Returns a reverse map of the table of given number or the Microsoft
cmap. I.e. given a glyph gives the Unicode value for it.

=cut

sub reverse
{
    my ($self, $tnum) = @_;
    my ($table) = defined $tnum ? $self->{'Tables'}[$tnum] : $self->find_ms;
    my (@res, $i, $s, $first);

    foreach $s (@{$table->{'val'}})
    {
        $first = $s->{'START'};
        map {$res[$_] = $first++} @{$s->{'val'}};
    }
    @res;
}

1;

=head1 BUGS

=item *

No support for format 2 tables (MBCS)

=head1 AUTHOR

Martin Hosken L<Martin_Hosken@sil.org>. See L<TTF::Font> for copyright and
licensing.

=cut

