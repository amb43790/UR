
package UR::ModuleLoader;

use strict;
use warnings;
use Class::Autouse;

Class::Autouse->autouse(\&dynamically_load_class);
Class::Autouse->sugar(\&define_class);

my %loading;

sub define_class {
    my ($class,$func,@params) = @_;
    return unless $UR::initialized;
    return unless $Class::Autouse::orig_can->("UR::Object::Type","get");

    #return if $loading{$class};    
    #$loading{$class} = 1;

    # Handle the special case of defining a new class
    # This lets us have the effect of a UNIVERSAL::class method, w/o mucking with UNIVERSAL
    if (defined($func) and $func eq "class" and @params > 1 and $class ne "UR::Object::Type") {
        my @class_params;
        if (@params == 2 and ref($params[1]) eq 'HASH') {
            @class_params = %{ $params[1] };
        }
        elsif (@params == 2 and ref($params[1]) eq 'ARRAY') {
            @class_params = @{ $params[1] };
        }
        else {
            @class_params = @params[1..$#params];
        }
        my $class_meta = UR::Object::Type->define(class_name => $class, @class_params);
        unless ($class_meta) {
            die "error defining class $class!";
        }
        return sub { $class };
    }
    else {
        return;
    }
}

sub dynamically_load_class {
    my ($class,$func,@params) = @_;
    # Don't even try to load unless we're done boostrapping somewhat.
    return unless $UR::initialized;
    return unless $Class::Autouse::orig_can->("UR::Object::Type","get");

    # Some modules (Class::DBI, recently) call UNIVERSAL::can directly with things which don't even resemble
    # class names.  Skip doing any work on anything which isn't at least a two-part class name.
    # We refuse explicitly to handle top-level namespaces below anyway, and this will keep us from 
    # slowing down other modules just to fail late.

    my ($namespace) = ($class =~ /^(.*?)::/);
    return unless $namespace;

    unless ($namespace->isa("UR::Namespace")) {
        return;
    }

    return if $loading{$class};    
    $loading{$class} = 1;

    # Attempt to get a class object, loading it as necessary (probably).
    my $meta = $namespace->get_member_class($class);
    unless ($meta) {
        delete $loading{$class};
        return;
    }

    my $class_module_dir = $meta->module_directory;
    if (defined $class_module_dir) {
        # Ensures that classes autoloaded from module files are under the correct
        # namespace.  Since there may be multiple namespaces under the same parent
        # dir, a hole exists in the above which should only be encountered
        # if someone is doing something odd with pkg/class mapping.
        my $namespace = $meta->namespace;
        unless ($namespace) {
            Carp::confess("Failed to resolve a namespace for Class object ".$meta->class_name);
        };
        unless ($namespace eq 'UR') {
            my $namespace_module_dir = $namespace->get_class_object->module_directory;
            unless ($class =~ /^UR::/ or index($class_module_dir,$namespace_module_dir) == 0) {
                Carp::confess(
                    "Attempt to load a module from outside the namespace tree!\n"
                    . "class path $class_module_dir is not under "
                    . "namespace $namespace_module_dir!\n"
                );
            }
        }
    }

    # Handle the case in which the class is not "generated".
    # These are generated by default when used, so this is a corner case.
    unless ($meta->generated())
    {
        # we have a new class
        # attempt to auto-generate it
        unless ($meta->generate)
        {
            Carp::confess("failed to auto-generate $class");
        }
    }

    delete $loading{$class};

    # Return a descriptive error message for the caller.
    my $fref;
    if (defined $func) {
        $fref = $class->can($func);
        unless ($fref) {
            Carp::confess("$class was auto-generated successfully but cannot find method $func");
        }
        return $fref;
    }

    return 1;
};

1;

