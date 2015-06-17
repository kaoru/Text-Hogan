package Hogan::Template;

use strict;
use warnings;
use boolean;

sub new {
    my $orig = shift;
    my ($code_obj, $text, $compiler, $options) = @_;

    $code_obj ||= {};

    my $class = ref($orig) || $orig;

    my $self = bless {}, $class;

    $self->{'r'} = $code_obj->{'code'} || (ref($orig) && $orig->{'r'});
    $self->{'c'} = $compiler;
    $self->{'options'} = $options || {};
    $self->{'text'} = $text || "";
    $self->{'partials'} = $code_obj->{'partials'} || {};
    $self->{'subs'} = $code_obj->{'subs'} || {};

    $self->{'buf'} = "";

    return $self;
}

sub r {
    my ($self, $context, $partials, $indent) = @_;

    if ($self->{'r'}) {
        return $self->{'r'}->($self, $context, $partials, $indent);
    }

    return "";
}

sub v {
    my ($self, $str) = @_;
    $str = $self->t($str);

    $str =~ s/&/&amp;/g;
    $str =~ s/</&lt;/g;
    $str =~ s/>/&gt;/g;
    $str =~ s/'/&#39;/g;
    $str =~ s/"/&quot;/g;

    return $str;
}

sub t {
    my ($self, $str) = @_;
    return $str // "";
}

sub render {
    my ($self, $context, $partials, $indent) = @_;
    return $self->ri([ $context ], $partials || {}, $indent);
}

sub ri {
    my ($self, $context, $partials, $indent) = @_;
    return $self->r($context, $partials, $indent);
}

sub ep {
    my ($self, $symbol, $partials) = @_;
    my $partial = $self->{'partials'}{$symbol};

    # check to see that if we've instantiated this partial before
    my $template = $partials->{$partial->{'name'}};
    if ($partial->{'instance'} && $partial->{'base'} eq $template) {
        return $partial->{'instance'};
    }

    if (!ref($template)) {
        if (!$self->{'c'}) {
            die "No compiler available";
        }
        $template = $self->{'c'}->compile($template, $self->{'options'});
    }

    if (!$template) {
        return undef;
    }

    $self->{'partials'}{$symbol}{'base'} = $template;

    if ($partial->{'subs'}) {
        # make sure we consider parent template now
        if (!$partials->{'stack_text'}) {
            $partials->{'stack_text'} = {};
        }
        for my $key (sort keys %{ $partial->{'subs'} }) {
            if (!$partials->{'stack_text'}{$key}) {
                $partials->{'stack_text'}{$key} =
                    $self->{'active_sub'} && $partials->{'stack_text'}{$self->{'active_sub'}}
                        ? $partials->{'stack_text'}{$self->{'active_sub'}}
                        : $self->{'text'};
            }
        }
        $template = create_specialized_partial($template, $partial->{'subs'}, $partial->{'partials'}, $self->{'stack_subs'}, $self->{'stack_partials'}, $self->{'stack_text'});
    }
    $self->{'partials'}{$symbol}{'instance'} = $template;

    return $template;
}

# tries to find a partial in the current scope and render it
sub rp {
    my ($self, $symbol, $context, $partials, $indent) = @_;
    my $partial = $self->ep($symbol, $partials);
    if (!$partial) {
        return "";
    }

    return $partial->ri($context, $partials, $indent);
}

# render a section
sub rs {
    my ($self, $context, $partials, $section) = @_;
    my $tail = $context->[-1];
    if (ref $tail ne 'ARRAY') {
        $section->($context, $partials, $self);
        return;
    }

    for (my $i = 0; $i < @$tail; $i++) {
        push @$context, $tail->[$i];
        $section->($context, $partials, $self);
        pop @$context;
    }
}

# maybe start a section
sub s {
    my ($self, $val, $ctx, $partials, $inverted, $start, $end, $tags) = @_;
    my $pass;
    if ((ref($val) eq 'ARRAY') && !@$val) {
        return false;
    }

    if (ref($val) eq 'CODE') {
        $val = $self->ms($val, $ctx, $partials, $inverted, $start, $end, $tags);
    }

    $pass = !!$val;

    if (!$inverted && $pass && $ctx) {
        push @$ctx, ((ref($val) eq 'ARRAY') || (ref($val) eq 'HASH')) ? $val : $ctx->[-1];
    }

    return $pass;
}

# find values with dotted names
sub d {
    my ($self, $key, $ctx, $partials, $return_found) = @_;
    my $found;

    # JavaScript split is super weird!!
    #
    # GOOD:
    # > "a.b.c".split(".")
    # [ 'a', 'b', 'c' ]
    #
    # BAD:
    # > ".".split(".")
    # [ '', '' ]
    #
    my @names;
    if ($key eq '.') {
        @names = ("", "");
    }
    else {
        @names = split m/[.]/, $key;
    }
    my $val = $self->f($names[0], $ctx, $partials, $return_found);

    my $do_model_get = $self->{'options'}{'model_get'};
    my $cx;

    if ($key eq '.' && (ref($ctx->[-2]) eq 'ARRAY')) {
        $val = $ctx->[-1];
    }
    else {
        for (my $i = 1; $i < @names; $i++) {
            $found = find_in_scope($names[$i], $val, $do_model_get);
            if (defined $found) {
                $cx = $val;
                $val = $found;
            }
            else {
                $val = "";
            }
        }
    }

    if ($return_found && !$val) {
        return false;
    }

    if (!$return_found && ref($val) eq 'CODE') {
        push @$ctx, $cx;
        $val = $self->mv($val, $ctx, $partials);
        pop @$ctx;
    }

    return $val;
}

# find values with normal names
sub f {
    my ($self, $key, $ctx, $partials, $return_found) = @_;
    my $val = false;
    my $v = undef;
    my $found = false;
    my $do_model_get = $self->{'options'}{'model_get'};

    for (my $i = @$ctx - 1; $i >= 0; $i--) {
        $v = $ctx->[$i];
        $val = find_in_scope($key, $v, $do_model_get);
        if (defined $val) {
            $found = true;
            last;
        }
    }

    if (!$found) {
        return $return_found ? false : "";
    }

    if (!$return_found && (ref($val) eq 'CODE')) {
        $val = $self->mv($val, $ctx, $partials);
    }

    return $val;
}

# higher order templates
sub ls {
    my ($self, $func, $cx, $ctx, $partials, $text, $tags) = @_;
    my $old_tags = $self->{'options'}{'delimiters'};

    $self->{'options'}{'delimiters'} = $tags;
    $self->b($self->ct(coerce_to_string($func->($self,$cx,$text,$ctx)), $cx, $partials));
    $self->{'options'}{'delimiters'} = $old_tags;

    return false;
}

# compile text
sub ct {
    my ($self, $text, $cx, $partials) = @_;
    if ($self->{'options'}{'disable_lambda'}) {
        die "Lambda features disabled";
    }
    return $self->{'c'}->compile($text, $self->{'options'})->render($cx, $partials);
}

# template result buffering
sub b {
    my ($self, $s) = @_;
    $self->{'buf'} .= $s;
}

sub fl {
    my ($self) = @_;
    my $r = $self->{'buf'};
    $self->{'buf'} = "";
    return $r;
}

# method replace section
sub ms {
    my ($self, $func, $ctx, $partials, $inverted, $start, $end, $tags) = @_;
    my $text_source;
    my $cx = $ctx->[-1];
    my $result = $func->($self, $cx);

    if (ref($result) eq 'CODE') {
        if ($inverted) {
            return true;
        }
        else {
            $text_source = ($self->{'active_sub'} && $self->{'subs_text'} && $self->{'subs_text'}{$self->{'active_sub'}})
                ? $self->{'subs_text'}{$self->{'active_sub'}}
                : $self->{'text'};
            return $self->ls($result, $cx, $ctx, $partials, substr($text_source,$start,$end), $tags);
        }
    }

    return $result;
}

# method replace variable
sub mv {
    my ($self, $func, $ctx, $partials) = @_;
    my $cx = $ctx->[-1];
    my $result = $func->($self,$cx);

    if (ref($result) eq 'CODE') {
        return $self->ct(coerce_to_string($result->($self,$cx)), $cx, $partials);
    }

    return $result;
}

sub sub {
    my ($self, $name, $context, $partials, $indent) = @_;
    my $f = $self->{'subs'}{$name};
    if ($f) {
        $self->{'active_sub'} = $name;
        $f->($context,$partials,$self,$indent);
        $self->{'active_sub'} = false;
    }
}

################################################

sub find_in_scope {
    my ($key, $scope, $do_model_get) = @_;
    my $val;

    if ($scope && ref($scope) eq 'HASH') {
        if (defined $scope->{$key}) {
            $val = $scope->{$key};
        }
        elsif ($do_model_get) {
            die "Do Model Get not implemented in Hogan.pm!";
        }
    }

    return $val;
}

sub create_specialized_partial {
    my ($instance, $subs, $partials, $stack_subs, $stack_partials, $stack_text) = @_;

    die "Hope we don't get here because this looks hairy!!";
}


sub coerce_to_string {
    my ($str) = @_;
    return $str // "";
}

1;
