# --
# HTML/Generic.pm - provides generic HTML output
# Copyright (C) 2001 Martin Edenhofer <martin+code@otrs.org>
# --
# $Id: Generic.pm,v 1.5 2001-12-16 01:41:27 martin Exp $
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see http://www.gnu.org/licenses/gpl.txt.
# --

package Kernel::Output::HTML::Generic;

use strict;
use MIME::Words qw(:all);
use Kernel::Language;

use vars qw($VERSION);
$VERSION = '$Revision: 1.5 $';
$VERSION =~ s/^.*:\s(\d+\.\d+)\s.*$/$1/;

sub new {
    my $Type = shift;
    my %Param = @_;

    my $Self = {}; # allocate new hash for object
    bless ($Self, $Type);

    # get common objects
    foreach (keys %Param) {
        $Self->{$_} = $Param{$_};
    }

    if (!$Self->{ConfigObject}) {
        die "Got no ConfigObject!";
    }

    $Self->{CGIHandle} = $Self->{ConfigObject}->Get('CGIHandle');

    $Self->{SessionID} = $Param{SessionID} || '';
    $Self->{Baselink}  = "$Self->{CGIHandle}?SessionID=$Self->{SessionID}";
    $Self->{Time}      = localtime();
    $Self->{Title}     = 'Open Ticket Request System' . ' - ' . $Self->{Time};
    $Self->{TableTitle}= 'OpenTRS - Open Ticket Request System';
    $Self->{HistoryCounter} = 0;

    # load theme
    my $Theme = $Self->{UserTheme} || 'Standard';

    # locate template files
    $Self->{TemplateDir} = '../../Kernel/Output/HTML/'. $Theme;

    # get log object
    $Self->{LogObject} = $Param{LogObject} || die "Got no LogObject!";

    # get config object
    $Self->{ConfigObject} = $Param{ConfigObject} || die "Got no Config!";

    # create language object
    $Self->{LanguageObject} = Kernel::Language->new(
      Language => $Self->{UserLanguage},
      LogObject => $Self->{LogObject},
    );

    return $Self;
}
# --
sub Output {
    my $Self = shift;
    my %Param = @_;
    my %Data = ();
    if ($Param{Data}) {
        my $Tmp = $Param{Data};
        %Data = %$Tmp;
    }

    # create %Env for this round!
    my %Env = ();
    if (!$Self->{EnvRef}) {
        # build OpenTRS env
        %Env = %ENV;
        $Env{SessionID} = $Self->{SessionID};
        $Env{Time} = $Self->{Time};
        $Env{CGIHandle} = $Self->{CGIHandle};
        $Env{Charset} = $Self->{Charset} || 'iso-8859-1';
        $Env{Baselink} = $Self->{Baselink};
    }
    else {
        # get %Env from $Self->{EnvRef} 
        my $Tmp = $Self->{EnvRef};
        %Env = %$Tmp;
    }

    # read template
    my $Output = '';
    open (IN, "< $Self->{TemplateDir}/$Param{TemplateFile}.dtl")  
         ||  die "Can't read $Param{TemplateFile}.dtl: $!";
    while (<IN>) {
      # filtering of comment lines
      if ($_ !~ /^#/) {
        $Output .= $_;

        # do template set (<dtl set $Data{"adasd"} = "lala">) 
        # do system call (<dtl system-call $Data{"adasd"} = "uptime">)
        $Output =~ s{
          <dtl\W(system-call|set)\W\$(Data|Env)\{\"(.+?)\"\}\W=\W\"(.+?)\">
        }
        {
          my $Data = '';
          if ($1 eq "set") {
            $Data = $4;
          }
          else {
            open (SYSTEM, " $4 | ") || print STDERR "Can't open $4: $!";
            while (<SYSTEM>) {
                $Data .= $_;
            }
            close (SYSTEM);      
          }

          if ($2 eq 'Data') {
              $Data{$3} = $Data;
          }
          elsif ($2 eq 'Env') {
              $Env{$3} = $Data;
          }
          "";
        }egx;


        # do template if dynamic
        $Output =~ s{
          <dtl\Wif\W\((\$.*)\{\"(.*)\"\}\W(eq|ne)\W\"(.*)\"\)\W\{\W\$(.*)\{\"(.*)\"\}\W=\W\"(.*)\";\W\}>
        }
        {
          if ($3 eq "eq") {
            if ($1 eq "\$Text") {
              if ($Self->{LanguageObject}->Get($2) eq $4) {
                  $Data{"$6"} = $7;
                  "";
              }
            }
            elsif ($1 eq "\$Data") {
              if ((exists $Data{"$2"}) && $Data{"$2"} eq $4) {
                  $Data{"$6"} = $7;
                  "";
              }
            }
            else {
                "Parser Error! '$1' is unknown!";
            }
         }
         elsif ($3 eq "ne") {
           if ($1 eq "\$Text") {
             if ($Self->{LanguageObject}->Get($2) ne $4) {
                 $Data{"$6"} = $7;
                 "";
             }
           }
           elsif ($1 eq "\$Data") {
              if (!exists $Data{"$2"}) {
                 $Data{"$6"} = $7;
                 "";
              }
              elsif ($Data{"$2"} ne $4) {
                 $Data{"$6"} = $7;
                 "";
              }
           }
           else {
               "Parser Error! '$1' is unknown!";
           }
         }
         else {
              "";
         }
      }egx;


      # variable & env & config replacement & text translation
      $Output =~ s{
        \$(Data|Env|Config|Text){"(.+?)"}
      }
      {
        if ($1 eq "Data") {
          if ($Data{$2}) {
              $Data{$2};
          }
          else {
#              "<i>\$$1 {$2} isn't true!</i>";
               "";
          }
        }
        elsif ($1 eq "Env") {
          if ($Env{$2}) {
              $Env{$2};
          }
          else {
              "<i>\$$1 {$2} isn't true!</i>";
          }
        }
        # replace with
        elsif ($1 eq "Config") {
          $Self->{ConfigObject}->Get($2) 
        }
        # do translation
        elsif ($1 eq "Text") {
          $Self->{LanguageObject}->Get($2) 
        }
      }egx;


      }
    }
 
    # save %Env
    $Self->{EnvRef} = \%Env;

    # return output
    return $Output;
}
# --
sub Redirect {
    my $Self = shift;
    my %Param = @_;
    my $ReUrl = $Self->{Baselink} . $Param{OP};
    (my $Output = <<EOF);
Content-Type: text/html
location: $ReUrl

EOF
    return $Output;
}
# --
sub Test {
    my $Self = shift;
    my %Param = @_;

    # get output 
    my $Output = $Self->Output(TemplateFile => 'Test', Data => \%Param);

    # return output
    return $Output;

}
# --
sub Login {
    my $Self = shift;
    my %Param = @_;

    # get output 
    my $Output = $Self->Output(TemplateFile => 'Login', Data => \%Param);

    # return output
    return $Output;

}
# --
sub Error {
    my $Self = shift;
    my %Param = @_;

    ($Param{Package}, $Param{Filename}, $Param{Line}, $Param{Subroutine}) = caller(0);
    ($Param{Package1}, $Param{Filename1}, $Param{Line1}, $Param{Subroutine1}) = caller(1);

    $Param{Version} = ("\$$Param{Package}". '::VERSION');
    $Param{Version} =~ s/(.*)/$1/ee;

    # get output 
    my $Output = $Self->Output(TemplateFile => 'Error', Data => \%Param);

    # return output
    return $Output;

}
# --
sub NavigationBar {
    my $Self = shift;
    my %Param = @_;

    # get output
    my $Output = $Self->Output(TemplateFile => 'NavigationBar', Data => \%Param);

    # return output
    return $Output;
}
# --
sub Header {
    my $Self = shift;
    my %Param = @_;

    # get output
    my $Output = $Self->Output(TemplateFile => 'Header', Data => \%Param);

    # return output
    return $Output;
}
# --
sub Footer {
    my $Self = shift;
    my %Param = @_;

    # get output
    my $Output = $Self->Output(TemplateFile => 'Footer', Data => \%Param);

    # return output
    return $Output;
}
# --


1;
 
