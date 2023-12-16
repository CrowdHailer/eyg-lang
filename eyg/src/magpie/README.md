# magpie

A Datalog query engine.

## Running

npx sirv ./public
http://localhost:8080/#vvalues,sversion,vversion,r0,sdriver,slitmus:1&vvalues,sdriver,vdriver,r0,sversion,vversion,r0,sreplicaCount,i0:1,2&ve,sversion,vversion:1&vid,ssystemFBS,vfbs,r0,sversion,vversion,r0,sdriver,snvstate:1,2

## Notes

Initial implementation follows from [this article](https://www.instantdb.com/essays/datalogjs)

How do you define a recursive query from here


sequel query
vactor,sperson/name,vname,vmovie,smovie/sequel,vsequel,r3,smovie/title,vsequel_name,r2,smovie/title,vmovie_name,r2,smovie/cast,r0,r3,smovie/cast,r0:1,5,4

probably any value can be deduplicated if shows up again. or is there interesting/standard compression algs?

Get the talk where the db tables became reports
have a drop down of values in attributes, or a did you mean.
discards
deleting element in query but not find shouldnt crash.

group by as reloading of a sub agg

movie_year ?name ?year

unbound(fn(actor) { unbound(f(year) {
    maybe maybe not
})})
xtdb and graph communities

always pass in a and add implicit rules of binding to a value

agg should always be a group
group(movie, sequel), name
which ones end up in groups, group vs set semantics, need list for count etc.

variables can have spaces etc so just use them as column names.


Static typing of datalog
https://www.learndatalogtoday.org/
rule for filtered db, i.e. part of a users organisation or particular cluster

terminus and xtdb community

xtdb or? or in args are available with use semantics.
and probably use is a way to work with all of the data log values

use a, b, c <- movie_year()
use a, b <- movie_year(1988)
ordering is a challenge

https://osquery.readthedocs.io/en/latest/introduction/using-osqueryi/
for os db

XTDB quinn haskell version OCAML https://www.google.com/url?sa=t&rct=j&q=&esrc=s&source=web&cd=&cad=rja&uact=8&ved=2ahUKEwii2IOG5vv8AhVq_bsIHTv_BB8QFnoECDMQAQ&url=https%3A%2F%2Fgithub.com%2Fc-cube%2Fdatalog&usg=AOvVaw3yViAmGsc5VEtILoLaO9km
args/inputs to queries -> rules
agg
predicates vs rule

https://dodisturb.me/posts/2018-12-25-The-Essence-of-Datalog.html bottom up


is datalog just reordering of tripple

"T1" sequel "T2"
"T2" sequel "T3"

name follow
find: ?m ?n
where:
    (OR [[?m sequel ?n]] [[follow ?m ?x] [?x sequel ?n]])

top level AND

follows(find: M, N) where: sequel(M, N)
follows(M, N) :- sequel(M, X) and follows(X, N)



Does predicates always go forward and if so can I have db's that look like generators, that look like property tests

Logic programming and it's relation to datalog needs to be understood.
- https://mercurylang.org/ strongly typed logic language, efficient implementation and compiler is built in it's self
  - used to have an erlang backend

Also what is minikanren vs prolog? is it just purity
- http://minikanren.org/minikanren-and-prolog.html most of the answer
  > Porting microKanren or miniKanren to a new host language has become a standard exercise for programmers learning miniKanren. As a result, most popular high-level languages have at least one miniKanren or microKanren implementation.
  Gleam/Eyg?
- https://www.researchgate.net/publication/228698350_Relational_Programming_in_miniKanren_Techniques_Applications_and_Implementations
- Warren Abstract machine was first fast compiler but other techniques have followed https://www.complang.tuwien.ac.at/andi/papers/wlp_94.pdf
- https://news.ycombinator.com/item?id=2152964
- more implenentation guidance https://cs.stackexchange.com/questions/6618/how-to-implement-a-prolog-interpreter-in-a-purely-functional-language
- Hitchhikers guide to reimplementing a prolog machine https://drops.dagstuhl.de/opus/volltexte/2018/8453/pdf/OASIcs-ICLP-2017-10.pdf
- The design and implementation of prolog https://core.ac.uk/download/pdf/228674394.pdf
- The power of Prolog https://www.metalevel.at/prolog
- https://www.metalevel.at/prolog/future
- https://github.com/mthom/scryer-prolog
    - https://news.ycombinator.com/item?id=28966133
- What happened to prolog https://www.kmjn.org/notes/prolog_lost_steam.html
- Datalog a precusor to prolog http://nickelsworth.github.io/sympas/16-datalog.html
- https://github.com/ysangkok/mitre-datalog.js
- https://wiki.nikiv.dev/programming-languages/prolog/datalog
- http://blogs.evergreen.edu/sosw/files/2014/04/Green-Vol5-DBS-017.pdf

Locigal query languae
- https://cse.buffalo.edu/~chomicki/636/a1.pdf
- http://www.cs.toronto.edu/~drosu/csc343-l7-handout6.pdf
- Data lectures datalog starts on https://pages.cs.wisc.edu/~paris/cs784-s17/lectures/
- Introduction to database https://www.classes.cs.uchicago.edu/archive/2007/spring/23500-1/slides/20_09May07.pdf
- http://infolab.stanford.edu/~ullman/fcdb/slides/slides14.pdf discussion of stratified
    - EDB = extensional database = relation stored in DB.
    - IDB = intensional database = relation defined by one or more rules.
- Datalog and emerging applications https://repository.upenn.edu/cgi/viewcontent.cgi?article=1735&context=cis_papers
- Foundations of databases http://webdam.inria.fr/Alice/
- Datalog and recursive queries https://piazza.com/class_profile/get_resource/hyiw0ttnku11l3/hzy4ey1jq3c66c
- Extending the power of recursion http://web.cs.ucla.edu/~zaniolo/papers/datalogFS.pdf
- Database systems https://courses.cs.duke.edu/fall17/compsci516/Lectures/Lecture-21-Datalog-notes.pdf
- https://github.com/quoll/asami/wiki

deductive spreadsheet
- XcelLog https://www3.cs.stonybrook.edu/~cram/Papers/RRW_KER07/paper.pdf
- https://www.cs.cmu.edu/~iliano/slides/cmu06.pdf The deductive spreadsheet
text based notebook builder

https://pages.iai.uni-bonn.de/manthey_rainer/IIS_1819/IIS18_Chapter2.pdf
