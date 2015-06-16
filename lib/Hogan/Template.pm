package Hogan::Template;

use strict;
use warnings;

sub new {
    my $class = shift;
    my ($code_obj, $text, $compiler, $options) = @_;

    $code_obj ||= {};

    my $self = bless {}, $class;

    $self->{'r'} = $code_obj->{'code'};
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
        if ($self->{'c'}) {
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

1;
