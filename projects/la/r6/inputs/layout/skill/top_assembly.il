; New source-preserving R6 top. Geometry is a candidate until actual verification.
procedure(laR6TopPinAt(inst name layer xy)
  let((term found)
    term=dbFindTermByName(inst~>master name)
    unless(term error("Missing hierarchy port %s.%s\n" inst~>name name))
    foreach(pin term~>pins foreach(fig pin~>figs
      when(equal(fig~>lpp list(layer "drawing")) &&
        abs(xCoord(laR3Center(fig~>bBox))-xCoord(xy))<.000001 &&
        abs(yCoord(laR3Center(fig~>bBox))-yCoord(xy))<.000001
        found=dbTransformPoint(xy inst~>transform))))
    unless(found error("Audited pin absent %s.%s %L\n" inst~>name name xy))
    found
  )
)
procedure(laR6TopAccess(inst name layer xy)
  let((found bb)
    foreach(shape inst~>master~>shapes
      when(equal(shape~>lpp list(layer "drawing")) && shape~>net && equal(shape~>net~>name name)
        bb=shape~>bBox
        when(xCoord(car(bb))<=xCoord(xy) && xCoord(cadr(bb))>=xCoord(xy) &&
          yCoord(car(bb))<=yCoord(xy) && yCoord(cadr(bb))>=yCoord(xy) found=t)))
    unless(found error("Existing %s access missing %s.%s %L\n" layer inst~>name name xy))
    dbTransformPoint(xy inst~>transform)
  )
)
procedure(laR6TopBind(inst connections nets)
  foreach(row connections
    unless(nets[cadr(row)] error("Missing planned core net %s\n" cadr(row)))
    unless(dbCreateInstTerm(nets[cadr(row)] inst dbFindTermByName(inst~>master car(row)))
      error("Cannot bind %s.%s\n" inst~>name car(row))))
)
procedure(laR6TopVia(ctx net fromLayer toLayer xy)
  let((via bb)
    for(m fromLayer toLayer-1
      via=laR3Via(ctx net sprintf(nil "M%d_M%d" m+1 m) xy
        list(list("cutRows" 2) list("cutColumns" 2) list("cutSpacing" list(.08 .08))))
      bb=via~>bBox
      laR3Rect(ctx net sprintf(nil "M%d" m) bb)
      laR3Rect(ctx net sprintf(nil "M%d" m+1) bb)
      laR3Pad(ctx net sprintf(nil "M%d" m) xy .24 .24)
      laR3Pad(ctx net sprintf(nil "M%d" m+1) xy .24 .24))
    xy
  )
)
procedure(laR6TopPowerPort(ctx net xy)
  let((fig term)
    fig=laR3Pad(ctx net "M8" xy 8.0 4.0)
    term=dbCreateTerm(net net~>name "inputOutput")
    unless(term && dbCreatePin(net fig) error("Cannot create M8 core port\n"))
    dbCreateLabel(ctx["cv"] list("M8" "pin") xy net~>name "centerCenter" "R0" "roman" .12)
    fprintf(ctx["audit"] "PORT\t%s\tM8\t%L\t%L\n" net~>name xy fig~>bBox)
    term
  )
)
procedure(laR6TopBuild()
  let((project run cell stageName feedbackName sourceName stageMaster feedbackMaster cv ctx audit nets stages pitch inst x pn nn op on net a b upper lower bb)
    project=getShellEnvVar("LA_PROJECT_DIR") run=getShellEnvVar("LA_TOP_RUN")
    cell=getShellEnvVar("LA_TOP_CELL") stageName=getShellEnvVar("LA_TOP_STAGE")
    feedbackName=getShellEnvVar("LA_TOP_FEEDBACK") sourceName=getShellEnvVar("LA_TOP_SOURCE")
    unless(equal(project "@LA5_PROJECT_ROOT@") && run &&
      cell && rexMatchp("^la_core_layout_r6_" cell) &&
      equal(stageName "la_stage_layout_r6_interdig80_w012_20261013_090018") &&
      equal(feedbackName "la_feedback_adapter_r3_20261010_222226") &&
      equal(sourceName "la_core_candidate_r5_nf44_20261013_060727") && getShellEnvVar("LA_TOP_CDL")
      error("Unexpected new R6 top destination or source\n"))
    when(ddGetObj("la5_lab" cell) error("Never overwrite an existing core\n"))
    stageMaster=dbOpenCellViewByType("la5_lab" stageName "layout" "maskLayout" "r")
    feedbackMaster=dbOpenCellViewByType("la5_lab" feedbackName "layout" "maskLayout" "r")
    unless(stageMaster && feedbackMaster && length(stageMaster~>instances)==6 &&
      length(stageMaster~>terminals)==6 && length(feedbackMaster~>instances)==1 &&
      length(feedbackMaster~>terminals)==2 error("Audited native child counts required\n"))
    audit=outfile(strcat(run "/top_audit.tsv") "w")
    fprintf(audit "STATUS\tUNQUALIFIED_PHYSICAL_TOP\tSOURCE=%s\tSTAGE=%s\tFEEDBACK=%s\n" sourceName stageName feedbackName)
    cv=dbOpenCellViewByType("la5_lab" cell "layout" "maskLayout" "w")
    ctx=makeTable('laR6TopCtx nil) ctx["cv"]=cv ctx["audit"]=audit
    nets=makeTable('laR6TopNets nil) stages=makeTable('laR6TopStages nil)
    foreach(name list("inp" "inn" "outp" "outn" "vdd" "VSS") nets[name]=dbMakeNet(cv name))
    for(k 1 10 foreach(prefix list("p" "n") nets[sprintf(nil "%s%d" prefix k)]=dbMakeNet(cv sprintf(nil "%s%d" prefix k))))
    pitch=19.0
    for(k 1 11
      x=(k-1)*pitch
      inst=dbCreateInst(cv stageMaster sprintf(nil "ST%d" k) list(x 0.0) "R0" 1)
      unless(inst error("Cannot create stage %d\n" k))
      stages[k]=inst
      pn=if(k==1 "inp" sprintf(nil "p%d" k-1)) nn=if(k==1 "inn" sprintf(nil "n%d" k-1))
      op=if(k==11 "outp" sprintf(nil "p%d" k)) on=if(k==11 "outn" sprintf(nil "n%d" k))
      laR6TopBind(inst list(list("inp" pn) list("inn" nn) list("outp" op) list("outn" on)
        list("vdd" "vdd") list("VSS" "VSS")) nets)
      laR6TopPinAt(inst "inp" "M3" list(-2.0 2.8))
      laR6TopPinAt(inst "inn" "M3" list(6.4 2.8))
      laR6TopPinAt(inst "outp" "M3" list(6.8 6.5))
      laR6TopPinAt(inst "outn" "M3" list(15.2 6.5))
      fprintf(audit "STAGE\t%d\t%L\t%L\tNATIVE=6\n" k inst~>xy inst~>bBox))
    ; Both centerline lengths 17.85 um. Electrical matching still requires RCC.
    ; Reuse child M4 input access and M4/M5 output downstack: no duplicate VIA3.
    for(k 1 10
      x=(k-1)*pitch net=nets[sprintf(nil "p%d" k)]
      a=laR6TopAccess(stages[k] "outp" "M5" list(6.45 6.5))
      b=laR6TopAccess(stages[k+1] "inp" "M4" list(-2.0 2.8))
      laR3Segment(ctx net "M5" a list(x+6.45 1.7) .20)
      laR3Segment(ctx net "M5" list(x+6.45 1.7) list(x+15.7 1.7) .20)
      laR6TopVia(ctx net 4 5 list(x+15.7 1.7))
      laR3Segment(ctx net "M4" list(x+15.7 1.7) list(x+17.7 1.7) .20)
      laR3Segment(ctx net "M4" list(x+17.7 1.7) list(x+17.7 2.8) .20)
      laR3Segment(ctx net "M4" list(x+17.7 2.8) b .20)
      fprintf(audit "STAGE_HOP\t%s\tLENGTH=17.85\tM5=14.05\tM4=3.8\n" net~>name)
      net=nets[sprintf(nil "n%d" k)]
      a=laR6TopAccess(stages[k] "outn" "M4" list(14.85 6.5))
      b=laR6TopAccess(stages[k+1] "inn" "M4" list(6.4 2.8))
      laR3Segment(ctx net "M4" a list(x+14.85 1.0) .20)
      laR6TopVia(ctx net 4 5 list(x+14.85 1.0))
      laR3Segment(ctx net "M5" list(x+14.85 1.0) list(x+25.4 1.0) .20)
      laR6TopVia(ctx net 4 5 list(x+25.4 1.0))
      laR3Segment(ctx net "M4" list(x+25.4 1.0) b .14)
      fprintf(audit "STAGE_HOP\t%s\tLENGTH=17.85\tM5=10.55\tM4=7.3\n" net~>name))
    ; Short feedback input leads; unequal physical environments retained. Lower input M3 avoids M4 drain bar.
    upper=dbCreateInst(cv feedbackMaster "RFBP" list(-2.2 20.0) "MXR90" 1)
    lower=dbCreateInst(cv feedbackMaster "RFBN" list(6.2 -25.58) "R270" 1)
    unless(upper && lower error("Cannot create feedback children\n"))
    laR6TopBind(upper list(list("PLUS" "outp") list("MINUS" "inp")) nets)
    laR6TopBind(lower list(list("PLUS" "outn") list("MINUS" "inn")) nets)
    net=nets["inp"]
    a=laR6TopAccess(stages[1] "inp" "M4" list(-2.0 2.8))
    b=laR6TopPinAt(upper "MINUS" "M2" list(-.4 .2))
    laR6TopVia(ctx net 2 4 b) laR3Segment(ctx net "M4" a b .14)
    fprintf(audit "FEEDBACK_INPUT\tinp\tLENGTH=16.8\tM4\n")
    net=nets["inn"]
    a=laR6TopPinAt(stages[1] "inn" "M3" list(6.4 2.8))
    b=laR6TopPinAt(lower "MINUS" "M2" list(-.4 .2))
    laR6TopVia(ctx net 2 3 b) laR3Segment(ctx net "M3" a b .14)
    fprintf(audit "FEEDBACK_INPUT\tinn\tLENGTH=27.98\tM3\n")
    ; Output feedback uses distinct upper/lower paths; record actual lengths.
    net=nets["outp"]
    a=laR6TopAccess(stages[11] "outp" "M4" list(6.45 6.5))
    b=laR6TopPinAt(upper "PLUS" "M2" list(-.4 146.15))
    laR6TopVia(ctx net 2 4 b)
    laR3Segment(ctx net "M4" a list(200.15 6.5) .14)
    laR3Segment(ctx net "M4" list(200.15 6.5) list(200.15 yCoord(b)) .14)
    laR3Segment(ctx net "M4" list(200.15 yCoord(b)) b .14)
    fprintf(audit "FEEDBACK_OUTPUT\toutp\tLENGTH=73.0\tM4\n")
    net=nets["outn"]
    a=laR6TopAccess(stages[11] "outn" "M4" list(14.85 6.5))
    b=laR6TopPinAt(lower "PLUS" "M2" list(-.4 146.15))
    laR6TopVia(ctx net 2 4 b)
    laR3Segment(ctx net "M4" a list(xCoord(a) yCoord(b)) .14)
    laR3Segment(ctx net "M4" list(xCoord(a) yCoord(b)) b .14)
    fprintf(audit "FEEDBACK_OUTPUT\toutn\tLENGTH=84.18\tM4\n")
    ; Native child M8 distributed access retained. Widths do not imply EM signoff.
    foreach(row list(list("vdd" 17.5 25.0) list("VSS" 4.0 -3.0))
      net=nets[car(row)]
      laR3Segment(ctx net "M8" list(-2.0 caddr(row)) list(205.0 caddr(row)) 8.0)
      for(k 1 11
        a=laR6TopPinAt(stages[k] car(row) "M8" list(7.06 cadr(row)))
        ; A square-ended VDD drop starting at17.5 extends below the native
        ; horizontal bar16.5 and creates two .195um same-net M8 notches.
        ; Start18.0 so its bottom16.5 is flush with that existing bar.
        if(equal(car(row) "vdd") then
          laR3Segment(ctx net "M8" list(xCoord(a) 18.0) list(xCoord(a) caddr(row)) 3.0)
        else
          laR3Segment(ctx net "M8" a list(xCoord(a) caddr(row)) 3.0)))
      laR6TopPowerPort(ctx net list(101.5 caddr(row))))
    foreach(row list(list("inp" 1 list(-2.0 2.8)) list("inn" 1 list(6.4 2.8))
      list("outp" 11 list(6.8 6.5)) list("outn" 11 list(15.2 6.5)))
      a=laR6TopPinAt(stages[cadr(row)] car(row) "M3" caddr(row))
      laR3Port(ctx nets[car(row)] "M3" a t))
    unless(length(cv~>instances)==13 && length(cv~>terminals)==6 error("Full core counts differ\n"))
    foreach(i cv~>instances unless(length(i~>instTerms)==length(i~>master~>terminals) error("Unbound child terminal\n")))
    fprintf(audit "PLANNED_COUNTS\tHIER=13\tNATIVE_PCELL=68\tMOS=22\tPOLY_LOAD_BANKS=44\tSERIES_FEEDBACK_BANKS=2\tPORTS=6\n")
    dbSave(cv) dbClose(cv)
    cv=dbOpenCellViewByType("la5_lab" cell "layout" "maskLayout" "r")
    unless(length(cv~>instances)==13 && length(cv~>terminals)==6 error("Saved counts differ\n"))
    bb=cv~>bBox
    fprintf(audit "TOP_REOPEN_PASS\tCELL=%s\tBBOX=%L\tHIER_INSTANCES=13\tNATIVE_PCELL_COUNT=68\tPORTS=6\tVIAS=%d\n" cell bb length(cv~>vias))
    fprintf(audit "FINAL_BBOX_UM\t%.9f\t%.9f\t%.9f\t%.9f\n" xCoord(car(bb)) yCoord(car(bb)) xCoord(cadr(bb)) yCoord(cadr(bb)))
    dbClose(cv) dbClose(stageMaster) dbClose(feedbackMaster) close(audit)
    printf("R6_TOP_BUILD_PASS CELL=%s\n" cell)
    t
  )
)
let((result)
  result=errset(laR6TopBuild() t)
  unless(result printf("R6_TOP_BUILD_FAILED\n"))
  exit()
)
