Edge cases for block scanning.

```lua
-- backtick fence with $x$, `code` and <!-- comment -->
```

~~~
tilde fence with $x$, `code` and <!-- comment -->
~~~

~~~python
x = 1  # tilde fence with a language
~~~

````
fence with ``` inside
````

Paragraph before an unclosed fence.

```
never closed $x$ <!-- c -->
