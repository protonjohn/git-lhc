# Configuration

LHC uses a configuration format that is useful for expressing variables as a matrix of conditions.

Sometimes it's difficult to cleanly express how a build should be configured because the environment variables depend on a difficult matrix of parameters. LHC's configuration format lets you concisely express which variables should be set to which values in a given context.

## Format

A basic line in a build configuration file looks like this:
```
property = value
```

A comment looks like this:
```
// This is a comment. It is not interpreted.
```

### Types
Everything in the build configuration is interpreted as a string by default, and these strings may not span multiple lines. However, there are two special values a type can have in addition to its defined value:

- A property is "truthy" if it is defined, and not set to "NO" or "false".
- A property is "falsey" if it is undefined, or is equal to either "NO" or "false".

If evaluating a configuration file with the `--format json` option specified, `git lhc config eval` will attempt to interpret basic types - booleans, ints, floats, strings, lists, and dictionaries - unless the `--no-typed-values` argument is passed.

### References

Properties can also reference one or more other properties:
```
property = $(property1) $(property2)
```

### Conditional Assignment

Where it gets interesting is when you start assigning values depending on the values other variables have been set to:
```
property[other_property=other_value] = value
```
In this case, `property` gets set to `value` only if `other_property=other_value`.

It's also possible to *chain* multiple conditions:
```
property[other_property=other_value][third_property=third_value] = value
```
In this case, `property` gets set to `value` only if `other_property=other_value` and `third_property=third_value`.

Checking whether a property is "truthy" or "falsey" can be done like this, respectively:
```
property[bool_property] = value

other_property[!bool_property] = value
```

In the first example, `property` only gets set if `bool_property` is set, and has a value other than `0` or `false`. In the second example, `other_property` only gets set if `bool_property` is not set, or has a value equal to `0` or `false`.

## Evaluation

The command `git lhc config eval` is available for evaluating piconf files. It takes one piconf file as an argument, along with a few other options (see `git lhc config eval --help` for more information).

Within a piconf file, properties referenced and declared are **not** evaluated successively. Rather, the configuration declarations in a piconf file describe a decision tree that is evaluated according to the initial values. Two rules which conflict will cause an error. For example, consider a file with these contents:
```
property[foo=Bar] = value
property[bar=Baz] = value2
```

This generates an error because the conditions `foo=Bar` and `bar=Baz` are not mutually exclusive, and it would be unclear which value to assign to `property` if both conditions return true.

If an assignment needs more than one condition, it should take the other conditional assignments for that property and form a chain of increasingly-specific, mutually-exclusive conditions, to avoid causing errors at evaluation time. An example of this is below:

```
property = defaultValue
property[bar=Baz] = value
property[!bar][foo=Bar] = value2
property[!bar][foo=Bar][fizz=Buzz] = value3
```

This example is valid because the `[!bar][foo=Bar]` and `[bar=Baz]` are mutually exclusive conditions, and are each subsets of the catch-all `defaultValue` case. Furthermore, the `[!bar][foo=Bar][fizz=Buzz]` case is allowed because it's more specific than the `[!bar][foo=Bar]` case.


For the purposes of maintaining the author's sanity, conditional assignments may not reference other variables in the assignment name, but they can be matched upon in variable names, where they will be expanded and integrated into the decision tree. So, this won't work: 
```
property[$(other_property)=value] = value
```

And neither will this:
```
property[other_property=$(value)] = value
```

But this will work:
```
property = $(other_property)
third_property[property=value] = dependent_value
```

### Expansion and Dependencies

When a property is referenced, i.e., something like `property2 = $(property)`, its value is evaluated when the variable is evaluated, and not immediately upon assignment, similar to a Makefile. Consider the lines:

```
property = $(property2)
property2 = value
```

This example will define two properties, `property` and `property2`, both with the value `value`. If two or more properties reference each other to create a cycle, `git lhc config eval` will generate an error. For example, consider the config elements below:

```
property = $(property2)
property2 = $(property)
```

These will cause an error because the two values are mutually dependent. The same can be said for situations involving conditional assignment, such as the example below:
```
property[property2] = property2IsSet
property2[!property] = propertyIsUnset
```

### Inherited values

In addition to referencing other values, conditional assignments can also reference their "parent" conditional assignment, which is the assignment with the next-most number of conditions that is also a subset of the given assignment. Assignments can reference this value by using the `$(inherited)` reference name. For example:

```
property = foo
property[foo] = $(inherited) true
property[!foo] = $(inherited) false
```

Here, `property` is set to `foo true` if `foo` is truthy, and `foo false` if `foo` is falsey.

An `$(inherited)` value at the top-level means that the config file author expects a user to provide a default value for the property. For example:

```
property = $(inherited)
property[foo] = foo true
```

Here, evaluation will fail with an error like "no default value provided for `property`" unless `foo` is truthy, in which case `property` will evaluate to `foo true`.
