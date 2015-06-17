package Hogan::Compiler;

use Hogan::Template;

use strict;
use warnings;
use boolean;

use Text::Trim 'trim';

my $r_is_whitespace = qr/\S/;
my $r_quot          = qr/"/;
my $r_newline       = qr/\n/;
my $r_cr            = qr/\r/;
my $r_slash         = qr/\\/;

my $linesep         = "\u{2028}";
my $paragraphsep    = "\u{2029}";
my $r_linesep       = qr/\Q$linesep\E/;
my $r_paragraphsep  = qr/\Q$paragraphsep\E/;

my %tags = (
    '#' => 1, '^' => 2, '<' => 3, '$' => 4,
    '/' => 5, '!' => 6, '>' => 7, '=' => 8, '_v' => 9,
    '{' => 10, '&' => 11, '_t' => 12
);

my $Template = Hogan::Template->new();

sub new {
    my $class = shift;
    return bless {}, $class;
}

sub scan {
    my ($self, $text, $delimiters) = @_;

    my ($len, $IN_TEXT, $IN_TAG_TYPE, $IN_TAG, $state, $tag_type, $tag, $buf, $tokens, $seen_tag, $i, $line_start, $otag, $ctag) = (
        length($text),
        0,
        1,
        2,
        0, # first state is $IN_TEXT
        undef,
        undef,
        "",
        [],
        false,
        0,
        0,
        '{{',
        '}}',
    );

    my $add_buf = sub {
        if (length $buf > 0) {
            push @$tokens, { 'tag' => '_t', 'text' => $buf };
            $buf = "";
        }
    };

    my $line_is_whitespace = sub {
        my $is_all_whitespace = true;
        for (my $j = $line_start; $j < @$tokens; $j++) {
            $is_all_whitespace =
                ($tags{$tokens->[$j]{'tag'}} < $tags{'_v'}) ||
                ($tokens->[$j]{'tag'} eq '_t' && $tokens->[$j]{'text'} !~ $r_is_whitespace);
            if (!$is_all_whitespace) {
                return false;
            }
        }
        return $is_all_whitespace;
    };

    my $filter_line = sub {
        my ($have_seen_tag, $no_new_line) = @_;

        $add_buf->();

        if ($have_seen_tag && $line_is_whitespace->()) {
            for (my $j = $line_start, my $next; $j < @$tokens; $j++) {
                if ($tokens->[$j]{'text'}) {
                    if (($next = $tokens->[$j+1]) && $next->{'tag'} eq '>') {
                        $next->{'indent'} = $tokens->[$j]{'text'};
                    }
                    splice(@$tokens,$j,1);
                }
            }
        }
        elsif (!$no_new_line) {
            push @$tokens, { 'tag' => "\n" };
        }

        $seen_tag = false;
        $line_start = @$tokens;
    };

    my $change_delimiters = sub {
        my ($text, $index) = @_;

        my $close = '=' . $ctag;
        my $close_index = index($text, $close, $index);
        my $delimiters = [
            split ' ', trim(
                substr($text, index($text, '=', $index) + 1, $close_index)
            )
        ];

        $otag = $delimiters->[0];
        $ctag = $delimiters->[-1];

        return $close_index + length($close) - 1;
    };

    if ($delimiters) {
        $delimiters = [ split ' ', $delimiters ];
        $otag = $delimiters->[0];
        $ctag = $delimiters->[1];
    }

    for (my $i = 0; $i < $len; $i++) {
        if ($state eq $IN_TEXT) {
            if (tag_change($otag, $text, $i)) {
                $i--;
                $add_buf->();
                $state = $IN_TAG_TYPE;
            }
            else {
                if (char_at($text, $i) eq "\n") {
                    $filter_line->($seen_tag);
                }
                else {
                    $buf .= char_at($text, $i);
                }
            }
        }
        elsif ($state eq $IN_TAG_TYPE) {
            $i += length($otag) - 1;
            $tag = $tags{char_at($text,$i + 1)};
            $tag_type = $tag ? char_at($text, $i + 1) : '_v';
            if ($tag_type eq '=') {
                $i = $change_delimiters->($text, $i);
                $state = $IN_TEXT;
            }
            else {
                if ($tag) {
                    $i++;
                }
                $state = $IN_TAG;
            }
            $seen_tag = $i;
        }
        else {
            if (tag_change($ctag, $text, $i)) {
                push @$tokens, {
                    'tag'   => $tag_type,
                    'n'     => trim($buf),
                    'otag'  => $otag,
                    'ctag'  => $ctag,
                    'i'     => (($tag_type eq '/') ? $seen_tag - length($otag) : $i + length($ctag)),
                };
                $buf = "";
                $i += length($ctag) - 1;
                $state = $IN_TEXT;
                if ($tag_type eq '{') {
                    if ($ctag eq '}}') {
                        $i++;
                    }
                    else {
                        clean_triple_stache($tokens->[-1]);
                    }
                }
                else {
                    $buf .= char_at($text, $i);
                }
            }
        }
    }

    $filter_line->($seen_tag, true);

    return $tokens;
}

sub clean_triple_stache {
    my ($token) = @_;

    if (substr($token->{'n'}, length($token->{'n'} - 1)) eq '}') {
        $token->{'n'} = substr($token->{'n'}, 0, length($token->{'n'}) - 1);
    }

    return;
}

sub tag_change {
    my ($tag, $text, $index) = @_;

    if (char_at($text, $index) ne char_at($tag, 0)) {
        return false;
    }

    for (my $i = 1, my $l = length($tag); $i < $l; $i++) {
        if (char_at($text, $index + $i) ne char_at($tag, $i)) {
            return false;
        }
    }

    return true;
}

my %allowed_in_super = (
    '_t' => true,
    "\n" => true,
    '$'  => true,
    '/'  => true,
);

sub build_tree {
    my ($tokens, $Kind, $stack, $custom_tags) = @_;
    my ($instructions, $opener, $tail, $token) = ([], undef, undef, undef);

    $tail = $stack->[-1];

    while (scalar @$tokens) {
        $token = shift @$tokens;

        if ($tail && $tail->{'tag'} eq '<' && !$allowed_in_super{$token->{'tag'}}) {
            die "Illegal content in < super tag.";
        }

        if ($tags{$token->{'tag'}} <= $tags{'$'} || is_opener($token, $custom_tags)) {
            push @$stack, $token;
            $token->{'nodes'} = build_tree($tokens, $token->{'tag'}, $stack, $custom_tags);
        }
        elsif ($token->{'tag'} eq '/') {
            if (!@$stack) {
                die "Closing tag without opener: /$token->{'n'}";
            }
            $opener = pop @$stack;
            if ($token->{'n'} ne $opener->{'n'} && !is_closer($token->{'n'}, $opener->{'n'}, $custom_tags)) {
                die "Nesting error: $opener->{'n'} vs $token->{'n'}";
            }
            $opener->{'end'} = $token->{'i'};
            return $instructions;
        }
        elsif ($token->{'tag'} eq "\n") {
            $token->{'last'} = (@$tokens == 0) || ($tokens->[0]{'tag'} == "\n");
        }

        push @$instructions, $token;
    }

    if (@$stack) {
        die "Missing closing tag: ", pop(@$stack)->{'n'};
    }

    return $instructions;
}

sub is_opener {
    my ($token, $tags) = @_;

    for (my $i = 0, my $l = scalar(@$tags); $i < $l; $i++) {
        if ($tags->[$i]{'o'} == $token->{'n'}) {
            $token->{'tag'} = '#';
            return true;
        }
    }

    return 0;
}

sub is_closer {
    my ($close, $open, $tags) = @_;

    for (my $i = 0, my $l = scalar(@$tags); $i < $l; $i++) {
        if ($tags->[$i]{'c'} eq $close && $tags->[$i]{'o'} eq $open) {
            return true;
        }
    }

    return 0;
}

sub stringify_substitutions {
    my $obj = shift;

    my @items;
    for my $key (sort keys %$obj) {
        push @items, sprintf('"%s": function(c,p,t,i) {%s}', esc($key), $obj->{$key});
    }

    return sprintf("{ %s }", join(",", @items));
}

sub stringify_partials {
    my $code_obj;

    my @partials;
    for my $key (sort keys %{ $code_obj->{'partials'} }) {
        push @partials, sprintf('"%s":{name:"%s", %s}',
            esc($code_obj->{'partials'}{$key}{'name'}),
            stringify_partials($code_obj->{'partials'}{$key})
        );
    }

    return sprintf("partials: {%s}, subs: %s",
        join(",", @partials),
        stringify_substitutions($code_obj->{'subs'})
    );
}

sub stringify {
    my ($code_obj, $text, $options) = @_;
    return sprintf('{ code => sub { my ($c,$p,$i) = @_; %s }, %s }',
        wrap_main($code_obj->{'code'}),
        stringify_partials($code_obj)
    );
}

my $serial_no = 0;
sub generate {
    my ($self, $tree, $text, $options) = @_;

    $serial_no = 0;

    my $context = { 'code' => "", 'subs' => {}, 'partials' => {} };
    walk($tree, $context);

    if ($options->{'as_string'}) {
        return stringify($context, $text, $options);
    }

    return $self->make_template($context, $text, $options);
}

sub wrap_main {
    my ($code) = @_;
    return sprintf('my $t = $self; $t->b($i = $i || ""); %s return $t->fl();', $code);
}

sub make_template {
    my $self = shift;
    my ($code_obj, $text, $options) = @_;

    my $template = make_partials($code_obj);
    $template->{'code'} = sub {
        my ($c, $p, $i) = @_;
        wrap_main($code_obj->{'code'});
    };
    return $Template->new($template, $text, $self, $options);
}

sub make_partials {
    my ($code_obj) = @_;

    my $key;
    my $template = {
        'subs'     => {},
        'partials' => $code_obj->{'partials'},
        'name'     => $code_obj->{'name'},
    };

    for my $key (sort keys %{ $template->{'partials'} }) {
        $template->{'partials'}{$key} = make_partials($template->{'partials'}{$key});
    }

    for my $key (sort keys %{ $code_obj->{'subs'} }) {
        $template->{'subs'}{$key} = sub {
            my ($c, $p, $t, $i) = @_;
            $code_obj->{'subs'}{$key};
        };
    }

    return $template;
}

sub esc {
    my $s = shift;

    $s =~ s/$r_slash/\\\\/g;
    $s =~ s/$r_quot/\\\"/g;
    $s =~ s/$r_newline/\\n/g;
    $s =~ s/$r_cr/\\r/g;
    $s =~ s/$r_linesep/\\u2028/g;
    $s =~ s/$r_paragraphsep/\\u2029/g;

    return $s;
}

sub char_at {
    my ($text, $index) = @_;
    return substr($text, $index, 1);
}

sub choose_method {
    my ($s) = @_;
    return $s =~ m/[.]/ ? "d" : "f";
}

sub create_partial {
    my ($node, $context) = @_;

    my $prefix = "<" . ($context->{'prefix'} || "");
    my $sym = $prefix . $node->{'n'} . $serial_no++;
    $context->{'partials'}{$sym} = {
        'name'     => $node->{'n'},
        'partials' => {},
    };
    $context->{'code'} += sprintf('$t->b($t->rp("%s",$c,$p,"%s"));',
        esc($sym),
        ($node->{'indent'} || "")
    );

    return $sym;
}

my %codegen = (
    '#' => sub {
        my ($node, $context) = @_;
        $context->{'code'} .= sprintf('if($t->s($t->%s("%s",$c,$p,1),$c,$p,0,%s,%s,"%s %s")) { $t->rs($c,$p,sub { my ($c,$p,$t) = @_;',
            choose_method($node->{'n'}),
            esc($node->{'n'}),
            $node->{'i'},
            $node->{'end'},
            $node->{'otag'},
            $node->{'ctag'}
        );
        walk($node->{'nodes'}, $context);
        $context->{'code'} .= "};";
    },
    '^' => sub {
        my ($node, $context) = @_;
        $context->{'code'} .= sprintf('if (!$t->s($t->%s("%s",$c,$p,1),$c,$p,1,0,0,"")){',
            choose_method($node->{'n'}),
            esc($node->{'n'})
        );
        walk($node->{'nodes'}, $context);
        $context->{'code'} .= "};";
    },
    '>' => \&create_partial,
    '<' => sub {
        my ($node, $context) = @_;
        my $ctx = { 'partials' => {}, 'code' => "", 'subs' => {}, 'in_partial' => true };
        walk($node->{'nodes'}, $ctx);
        my $template = $context->{'partials'}{create_partial($node, $context)};
        $template->{'subs'} = $ctx->{'subs'};
        $template->{'partials'} = $ctx->{'partials'};
    },
    '$' => sub {
        my ($node, $context) = @_;
        my $ctx = { 'subs' => {}, 'code' => "", 'partials' => $context->{'partials'}, 'prefix' => $node->{'n'} };
        walk($node->{'nodes'}, $ctx);
        $context->{'subs'}{$node->{'n'}} = $ctx->{'code'};
        if (!$context->{'in_partial'}) {
            $context->{'code'} += sprintf('$t->sub("%s",$c,$p,$i);',
                esc($node->{'n'})
            );
        }
    },
    "\n" => sub {
        my ($node, $context) = @_;
        $context->{'code'} .= twrite(sprintf('"\n"%s', ($node->{'last'} ? "" : ' + $i')));
    },
    '_v' => sub {
        my ($node, $context) = @_;
        $context->{'code'} .= twrite(sprintf('$t->v($t->%s("%s",$c,$p,0))',
            choose_method($node->{'n'}),
            esc($node->{'n'})
        ));
    },
    '_t' => sub {
        my ($node, $context) = @_;
        $context->{'code'} .= twrite(sprintf('"%s"', esc($node->{'text'})));
    },
    '{' => \&triple_stache,
    '&' => \&triple_stache,
);

sub triple_stache {
    my ($node, $context) = @_;
    $context->{'code'} += sprintf('$t->b($t->t($t->%s("%s",$c,$p,0)))',
        choose_method($node->{'n'}),
        esc($node->{'n'})
    );
}

sub twrite {
    my ($s) = @_;
    return sprintf('$t->b(%s);', $s);
}

sub walk {
    my ($nodelist, $context) = @_;
    my $func;
    for (my $i = 0, my $l = scalar(@$nodelist); $i < $l; $i++) {
        $func = $codegen{$nodelist->[$i]{'tag'}};
        $func && $func->($nodelist->[$i], $context);
    }
    return $context;
}

sub parse {
    my ($self, $tokens, $text, $options) = @_;
    $options ||= {};
    return build_tree($tokens, "", [], $options->{'selection_tags'} || []);
}

my %cache;

sub cache_key {
    my ($text, $options) = @_;
    return join("||", $text, !!$options->{'as_string'}, !!$options->{'disable_lambda'}, ($options->{'delimiters'} // ""), !!$options->{'model_get'});
}

sub compile {
    my ($self, $text, $options) = @_;
    $options ||= {};
    my $key = cache_key($text, $options);
    my $template = $cache{$key};

    if ($template) {
        my $partials = $template->{'partials'};
        for my $name (sort keys %{ $template->{'partials'} }) {
            delete $partials->{$name}{'instance'};
        }
        return $template;
    }

    $template = $self->generate(
        $self->parse(
            $self->scan($text, $options->{'delimiters'}), $text, $options
        ), $text, $options
    );

    return $cache{$key} = $template;
}

1;
