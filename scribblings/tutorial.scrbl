#lang scribble/doc
@require[scribble/manual
         scribble-abbrevs/manual
         scribble/example
         racket/sandbox
         @for-label[qi
                    racket
                    (only-in relation
                             ->number
                             ->string
                             sum)]]

@(define eval-for-docs
  (parameterize ([sandbox-output 'string]
                 [sandbox-error-output 'string]
                 [sandbox-memory-limit #f])
    (make-evaluator 'racket/base
                    '(require qi
                              (only-in racket/list range)
                              racket/string
                              relation)
                    '(define (sqr x)
                       (* x x)))))

@title{Tutorial: When Should I Use Qi?}

Okay, so you've read @secref["Usage"] and can write some simple flows. Let's now look at a collection of examples that may help shed light on when you should use Qi vs Racket or another language.

@table-of-contents[]

@section{Hadouken!}

When you're interested in transforming values, Qi is often the right language to use.

@subsection{Super Smush Numbers}

Let's say we'd like to define a function that adds together all of the input numbers, except that instead of using usual addition, we want to just adjoin them ("smush them") together to create a bigger number as the result.

In Qi, we could express it this way:

@codeblock{
  (define-flow smush
    (~> (>< ->string)
        string-append
        ->number))
}

The equivalent in Racket would be:

@codeblock{
  (define (smush . vs)
    (->number
     (apply string-append
            (map ->string vs))))
}

The Qi version uses @racket[><] to "map" all input values under the @racket[->string] flow to convert them to strings. Then it appends these values together as strings, finally converting the result back to a number to produce the result.

The Racket version needs to be parsed in detail in order to be understood, while the Qi version reads sequentially in the natural order of the transformations, and makes plain what these transformations are. Qi is the natural choice here.

The documentation for the @seclink["top" #:doc '(lib "scribblings/threading.scrbl")]{threading macro} contains additional examples of such transformations which to a first approximation apply to Qi as well (see @secref["Relationship_to_the_Threading_Macro"]).

@subsection{Root-Mean-Square}

While you can always use Qi to express computations as flows, it isn't always a better way of thinking about them -- just a @emph{different} way, better in some cases but not others. Let's look at an example that illustrates this subjectivity.

The "root mean square" is a measure often used in statistics to estimate the magnitude of some quantity for which there are many independent measurements. For instance, given a set of values representing the "deviation" of the result from the predictions of a model, we can use the square root of the mean of the squares of these values as an estimate of "error" in the model, i.e. inversely, an estimate of the accuracy of the model. The RMS also comes up in other branches of engineering and mathematics. What if we encountered such a case and wanted to implement this function? In Racket, we might implement it as:

@codeblock{
    (define (rms vs)
      (sqrt (/ (apply + (map sqr vs))
               (length vs))))
}

In Qi, it would be something like:

@codeblock{
    (define-flow rms
      (~> (-< (~> △ (>< sqr) +)
              length) / sqrt))
}

This first uses the tee junction, @racket[-<], to fork the input down two flows, one to compute the sum of squares and the other to compute the length. In computing the sum of squares, the input list is first separated into its component values using @racket[△]. Then, @racket[><] "maps" these values under the @racket[sqr] flow to yield the squares of the input values which are then summed. These values are combined downstream to yield the mean of the squares, whose square root produced as the result.

Here, there are reasons to favor either representation. The Racket version doesn't have too much redundancy so it is a fine way to express the computation. The Qi version eliminates the redundant references to the input (as it usually does), but aside from that it is primarily distinguished as being a way to express the computation as a series of transformations evaluated sequentially, while the Racket version expresses it as a compound expression to be evaluated hierarchically. They're just @emph{different} and neither is necessarily better.

@section{The Science of Deduction}

When you seek to analyze some values and make inferences or assertions about them, or take certain actions based on observed properties of values, or, more generally, when you seek to express anything exhibiting @emph{subject-predicate structure}, Qi is often the right language to use.

@subsection{Compound Predicates}

In Racket, if we seek to make a compound assertion about some value, we might do something like this:

@codeblock{
  (λ (num)
    (and (positive? num)
         (integer? num)
         (= 0 (remainder num 3))))
}

This recognizes positive integers divisible by three. Using the utilities in @secref["Additional_Higher-Order_Functions"
         #:doc '(lib "scribblings/reference/reference.scrbl")], we might write it as:

@codeblock{
  (conjoin positive?
           integer?
           (compose (curry = 0) (curryr remainder 3)))
}

... which avoids the wrapping lambda, doesn't mention the argument redundantly, and transparently encodes the fact that the function is a compound predicate. On the other hand, it is arguably less easy on the eyes. For starters, it uses the word "conjoin" to avoid colliding with "and," to refer to a similar idea. It also uses the words "curry" and "curryr" to partially apply functions, which are somewhat gratuitous as ways of saying "equal to zero" and "remainder by three."

In Qi, this would be written as:

@codeblock{
  (and positive?
       integer?
       (~> (remainder 3) (= 0)))
}

They say that perfection is achieved not when there is nothing left to add, but when there is nothing left to take away. Well then.

@subsection{abs}

Let's say we want to implement @racket[abs]. This is a function that returns the absolute value of the input argument, i.e. the value unchanged if it is positive, and negated otherwise -- a conditional transformation. With Racket, we might implement it like this:

@codeblock{
    (define (abs v)
      (if (negative? v)
          (- v)
          v))
}

For this very simple function, the input argument is mentioned @emph{four} times! An equivalent Qi definition is:

@codeblock{
    (define-switch abs-value
      [negative? -]
      [else _])
}

This uses the definition form of @racket[switch], which is a flow-oriented conditional analogous to @racket[cond]. The @racket[_] symbol here indicates that the input is to be passed through unchanged, i.e. it is the trivial or identity flow. The input argument is not mentioned; rather, the definition expresses @racket[abs] as a conditioned transformation of the input, that is, the essence of what this function is.

@section{The Structure and Interpretation of Flows}

Sometimes, it is natural to express the entire computation as a flow, while at other times it may be better to express just a part of it as a flow. In either case, the most natural representation may not be apparent at the outset, by virtue of the fact that we don't always understand the computation at the outset. In such cases, it may make sense to take an incremental approach.

The classic Computer Science textbook, "The Structure and Interpretation of Computer Programs," contains the famous "metacircular evaluator" -- a Scheme interpreter written in Scheme. The code given for the @racket[eval] function is:

@codeblock{
    (define (eval exp env)
      (cond [(self-evaluating? exp) exp]
            [(variable? exp) (lookup-variable-value exp env)]
            [(quoted? exp) (text-of-quotation exp)]
            [(assignment? exp) (eval-assignment exp env)]
            [(definition? exp) (eval-definition exp env)]
            [(if? exp) (eval-if exp env)]
            [(lambda? exp) (make-procedure (lambda-parameters exp)
                                           (lambda-body exp)
                                           env)]
            [(begin? exp) (eval-sequence (begin-actions exp) env)]
            [(cond? exp) (eval (cond->if exp) env)]
            [(application? exp) (apply (eval (operator exp) env)
                                       (list-of-values (operands exp) env))]
            [else (error "Unknown expression type -- EVAL" exp)]))
}

This implementation in Racket mentions the expression to be evaluated, @racket[exp], @emph{twenty-five} times. This kind of redundancy is often a sign that the computation can be profitably thought of as a flow. In the present case, we notice that every condition in the @racket[cond] expression is a predicate applied to @racket[exp]. It would seem that it is the expression @racket[exp] that flows, here, through a series of checks and transformations in the context of some environment @racket[env]. By modeling the computation this way, we derive the following implementation:

@codeblock{
    (define (eval exp env)
      (switch (exp)
        [self-evaluating? _]
        [variable? (lookup-variable-value env)]
        [quoted? text-of-quotation]
        [assignment? (eval-assignment env)]
        [definition? (eval-definition env)]
        [if? (eval-if env)]
        [lambda? (~> (-< lambda-parameters
                         lambda-body) (make-procedure env))]
        [begin? (~> begin-actions (eval-sequence env))]
        [cond? (~> cond->if (eval env))]
        [application? (~> (-< (~> operator (eval env))
                              (~> operands △ (>< (eval env)))) apply)]
        [else (error "Unknown expression type -- EVAL" _)]))
}

This version eliminates two dozen redundant references to the input expression that were present in the original Racket implementation, and reads naturally. As it uses partial application @seclink["Templates_and_Partial_Application"]{templates} in the consequent flows, this version could be considered a hybrid implementation in Qi and Racket.

Yet, an astute observer may point out that although this eliminates almost all mention of @racket[exp], that it still contains @emph{ten} references to the environment, @racket[env]. In our first attempt at a flow-oriented implementation, we chose to see the @racket[eval] function as a flow of the input @emph{expression} through various checks and transformations. We were led to this choice by the observation that all of the conditions in the original Racket implementation were predicated exclusively on @racket[exp]. But now we see that almost all of the consequent expressions use the @emph{environment}, in addition. That is, it would appear that the environment @racket[env] @emph{flows} through the consequent expressions.

For such cases, by means of a @racket[divert] (or its alias, @racket[%]) clause "at the floodgates," the @racket[switch] form allows us to control which values flow to the predicates and which ones flow to the consequents. In the present case, we'd like the predicates to only receive the input @emph{expression}, and the consequents to receive both the expression as well as the environment. By modeling the flow this way, we arrive at the following pure-Qi implementation.

@codeblock{
  (define-switch eval
    (% 1> _)
    [self-evaluating? 1>]
    [variable? lookup-variable-value]
    [quoted? (~> 1> text-of-quotation)]
    [assignment? eval-assignment]
    [definition? eval-definition]
    [if? eval-if]
    [lambda? (~> (== (-< lambda-parameters
                         lambda-body)
                     _) make-procedure)]
    [begin? (~> (== begin-actions
                    _) eval-sequence)]
    [cond? (~> (== cond->if
                   _) eval)]
    [application? (~> (-< (~> (== operator
                                  _) eval)
                          (~> (== operands
                                  _) (△ eval))) apply)]
    [else (error "Unknown expression type -- EVAL" 1>)])
}

This version eliminates the more than @emph{thirty} mentions of the inputs to the function that were present in the Racket version, while introducing four flow references (i.e. @racket[1>]). Some of the clauses are unsettlingly elementary, reading like pseudocode rather than a real implementation, while other clauses become complex flows reflecting the path the inputs take through the expression. This version is stripped down to the essence of what the @racket[eval] function @emph{does}, encoding a lot of our understanding syntactically that otherwise is gleaned only by manual perusal -- for instance, the fact that @emph{all} of the predicates are only concerned with the input expression is apparent on the very first line of the switch body. The complexity in this implementation reflects the complexity of the computation being modeled, nothing more.

While the purist may favor this last implementation, it is a matter of some subjectivity, and some may prefer the compromise between minimalism and familiarity that the hybrid solution represents. Indeed, while the last solution is conceptually the most economical, the hybrid solution turns out to be the most lexically economical, i.e. the shortest in terms of number of characters (although, arguably conceptual economy is the more pertinent criterion since syntax need not be text-based). The original Racket implementation is in third place on both counts.

@section{Using the Right Tool for the Job}

We've seen a number of examples covering transformations, predicates, and conditionals, both simple and complex, where using Qi to describe the computation was often a natural and elegant choice.

The examples hopefully illustrate an age-old doctrine -- use the right tool for the job. A language is the best tool of all, so use the right language to express the task at hand. Sometimes, that language is Qi and sometimes it's Racket and sometimes it's a combination of the two, or something else. Don't try too hard to coerce the computation into one way of looking at things. It's less important to be consistent and more important to be fluent and clear. And by the same token, it's less important for you to fit your brain to the language and more important for the language to be apt to describe the computation, and consequently for it to encourage a way of thinking about the problem that fits your brain.

Employing a potpourri of general purpose and specialized languages, perhaps, is the best way to flow!
