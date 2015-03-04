%% The main module.
-module(measure).
-export([measure/4]).
-include("measure.hrl").
-include_lib("eqc/include/eqc.hrl").

measure(Rounds, MaxSize, Family, Axes) ->
  eqc_gen:pick(true),
  Results =
    [ round(I*2 + case Kind of worst -> -1; best -> 0 end, Kind, MaxSize, Family, Axes)
    || I <- lists:seq(1, Rounds),
       Kind <- [worst, best]],
  if Family#family.warmup -> ok;
     true ->
       io:format("~nFitting data.~n~n"),
       fit:fit(Axes#axes.outliers, lists:concat(Results))
  end.

round(I, Kind, MaxSize, Family, Axes) ->
  if Family#family.warmup -> ok;
     true -> io:format("~p. ~s case.~n", [I, kind_name(Kind)])
  end,
  Axes1 = kind_axes(Axes, Kind),
  Frontier = #frontier{inert = [], ert = [point(Family#family.initial, Axes1)]},
  Result = run(0, Frontier, MaxSize, Family, Axes1),
  Worst = worst_case(Result),
  if Family#family.warmup -> ok;
     true -> io:format("~n~p~n~n", [Worst])
  end,
  [ kind_point(X, Kind) || X <- Result ].

kind_name(worst) -> "Worst";
kind_name(best) -> "Best".
kind_axes(Axes, worst) -> Axes;
kind_axes(Axes, best) ->
  #axes {
     size = Axes#axes.size,
     time = negate(Axes#axes.time),
     measurements = lists:map(fun negate/1, Axes#axes.measurements)
    }.
kind_point(Point, worst) -> Point;
kind_point(Point=#point{coords = [Size|Coords]}, best) ->
  Point#point{coords = [Size|[-Coord || Coord <- Coords]]}.

worst_case(Xs) ->
  MaxSize = having_maximum(fun(#point{coords=[Size|_]}) -> Size end, Xs),
  [#point{value=Value}|_] = having_maximum(fun(#point{coords=[_,Time|_]}) -> Time end, MaxSize),
  Value.

having_maximum(F, Xs) ->
  Maximum = lists:max(lists:map(F, Xs)),
  [ X || X <- Xs, F(X) == Maximum ].

run(_Count, #frontier{inert = Inert, ert = []}, _, _, _) ->
  Inert;
run(Count, #frontier{inert = Inert, ert = [Cand|Ert]}, MaxSize, Family=#family{grow = Grow}, Axes) ->
  Frontier1 = #frontier{inert = [Cand|Inert], ert = Ert},
  Z = eqc_gen:pick(Grow(Cand#point.value)),
  Cands = [ point(Value, Axes) || Value <- lists:usort(Z) ],
  Count2 = Count + length(Cands),
  Cands1 = [ C || C=#point{coords=[Size|_]} <- Cands, Size =< MaxSize ],
  Frontier2 = add_cands_to_frontier(Count2, Cands1, Frontier1, Axes),
  run(Count2, Frontier2, MaxSize, Family, Axes).

point(Value, Axes) ->
  %% OBS we use both size and -size as measurements,
  %% so that a test case only dominates test cases with the same size,
  %% and we get one test case for each size
  Funs = [Axes#axes.size, Axes#axes.time, negate(Axes#axes.size)|Axes#axes.measurements],
  #point{value = Value, coords = [ F(Value) || F <- Funs ]}.

negate(F) -> fun(X) -> -F(X) end.

add_cands_to_frontier(Count, Cands, Frontier, Axes) ->
  #frontier{inert = Inert, ert = Ert} =
    lists:foldl(fun(C, F) -> add_to_frontier(Count, C, F, Axes) end, Frontier, Cands),
  #frontier{inert = Inert, ert = lists:usort(Ert)}.

improve(Cand, Axes) ->
  Cands = [ point(Cand#point.value, Axes) || _ <- lists:seq(1, Axes#axes.repeat) ],
  lists:min([Cand|Cands]).

add_to_frontier(Count, Cand, Frontier=#frontier{inert=Inert, ert=Ert}, Axes) ->
  case [ X || X <- Inert ++ Ert, dominates(X, Cand) ] of
    [_|_] -> Frontier;
    [] ->
      Cand1 = improve(Cand, Axes),
      case [ X || X <- Inert ++ Ert, dominates(X, Cand1) ] of
        [_|_] -> Frontier;
        [] ->
          Inert1 = [ X || X <- Inert, not dominates(Cand1, X) ],
          Ert1 = [ X || X <- Ert, not dominates(Cand1, X) ],
          %io:format("."),
          {Coords1, [_|Coords2]} = lists:split(2, Cand1#point.coords),
          io:format(" ~p (~p,~p)           \r", [Coords1 ++ Coords2, Count, length(Ert1)]),
          #frontier{inert=Inert1, ert=[Cand1|Ert1]}
      end
  end.

dominates(X, Y) ->
  lists:all(fun({A, B}) -> A >= B end, lists:zip(X#point.coords, Y#point.coords)).
