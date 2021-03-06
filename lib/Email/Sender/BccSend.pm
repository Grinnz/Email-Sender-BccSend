package Email::Sender::BccSend;

use strict;
use warnings;
use Email::Abstract;
use Email::Address::XS 'parse_email_addresses';
use Email::Sender::Failure::Permanent;
use Email::Sender::Failure::Multi;
use Email::Sender::Success;
use Email::Sender::Success::Partial;
use Email::Sender::Simple 'sendmail';
use Exporter 'import';
use Scalar::Util 'blessed';

our $VERSION = '0.001';

our @EXPORT_OK = qw(bcc_sendmail bcc_try_to_sendmail);

sub bcc_sendmail {
  my ($msg, $opts) = @_;
  $opts = {} unless defined $opts;
  my $email = Email::Abstract->new($msg);
  my @bccs = grep { defined } map { parse_email_addresses $_ } $email->get_header('bcc');
  $email->set_header('bcc'); # clear Bcc header

  my @results;
  my $failure = 1;

  # send to standard recipients
  if ($opts->{to} or $email->get_header('to') or $email->get_header('cc')) {
    my $result = _send($email, $opts);
    $failure = 0 if $result->isa('Email::Sender::Success');
    push @results, $result;
  }

  # send to bcc recipients
  foreach my $bcc (@bccs) {
    $email->set_header(Bcc => $bcc->original);
    local $opts->{to} = $bcc->address;
    my $result = _send($email, $opts);
    $failure = 0 if $result->isa('Email::Sender::Success');
    push @results, $result;
  }

  if ($failure) {
    Email::Sender::Failure::Multi->throw(message => 'all emails failed to send', failures => \@results);
  } else {
    # success, mixed successes, or partial successes
    my @failures;
    foreach my $result (@results) {
      if ($result->isa('Email::Sender::Failure')) {
        push @failures, $result;
      } elsif ($result->isa('Email::Sender::Success::Partial')) {
        push @failures, $result->failure->failures;
      }
    }
    return Email::Sender::Success->new unless @failures;
    return Email::Sender::Success::Partial->new(
      failure => Email::Sender::Failure::Multi->new(
        message => 'some emails failed to send',
        failures => \@failures,
      ),
    );
  }
}

sub bcc_try_to_sendmail {
  my @args = @_;
  my $result;
  local $@;
  return !!0 unless eval { $result = bcc_sendmail @args; 1 };
  return $result;
}

sub _send {
  my @args = @_;
  my $result;
  local $@;
  $result = $@ unless eval { $result = sendmail @args; 1 };
  return blessed $result ? $result : Email::Sender::Failure::Permanent->new(message => $result || 'Error');
}

1;

=head1 NAME

Email::Sender::BccSend - Send email simply, also to Bcc addresses

=head1 SYNOPSIS

  use Email::Sender::BccSend 'bcc_sendmail';
  my $result = bcc_sendmail $email;

=head1 DESCRIPTION

L<Email::Sender::BccSend> is a wrapper of L<Email::Sender::Simple> that
extracts C<Bcc> headers and sends the message individually to each specified
recipient, similar to how C<Bcc> is commonly handled by email clients. Because
it sends several emails, partial success is always possible.

=head1 FUNCTIONS

All functions are exported on demand.

=head2 bcc_sendmail

  my $result = bcc_sendmail $email;
  my $result = bcc_sendmail $email, $options;

Extracts the C<Bcc> header from the given email, which can be in any format
recognized by L<Email::Abstract>. The email is sent normally by
L<Email::Sender::Simple> without the C<Bcc> header, then sent to each C<Bcc>
recipient individually with a C<Bcc> header containing that recipient. 
Options may be specified the same way as in
L<"sendmail" in Email::Sender::Simple|Email::Sender::Manual::QuickStart>.

If all emails fail to send, an L<Email::Sender::Failure::Multi> exception will
be thrown. Otherwise an L<Email::Sender::Success> object will be returned. If
some emails failed to send or were a partial success, this object will be an
instance of the L<Email::Sender::Success::Partial> subclass.

  use Syntax::Keyword::Try;
  try {
    $result = bcc_sendmail $email;
    if ($result->isa('Email::Sender::Success::Partial') {
      print "partial success\n";
      print $_->message . "\n" foreach $result->failure->failures;
    } else {
      print "success\n";
    }
  } catch {
    print "failure\n";
    print $_->message . "\n" foreach $@->failures;
  }

If the email is passed as an object, this object may have its C<Bcc> header(s)
altered or removed so you should not depend on it remaining unchanged after the
call.

=head2 bcc_try_to_sendmail

  my $result = bcc_try_to_sendmail $email;
  my $result = bcc_try_to_sendmail $email, $options;

Like L</"bcc_sendmail">, but returns false instead of throwing an exception on
failure.

=head1 BUGS

Report any issues on the public bugtracker.

=head1 AUTHOR

Dan Book <dbook@cpan.org>

=head1 COPYRIGHT AND LICENSE

This software is Copyright (c) 2018 by Dan Book.

This is free software, licensed under:

  The Artistic License 2.0 (GPL Compatible)

=head1 SEE ALSO

L<Email::Sender::Manual::QuickStart>
