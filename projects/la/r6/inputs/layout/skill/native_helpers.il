; Create only new independent LA schematics from reviewed manifest data.
; Required LA_PROJECT_DIR, LA_OA_RUN_DIR, LA_OA_DATA, correct -cdslib.
; Rows: name lib cell x y orientation connections props callbacks verify mode.

procedure(laOaMaster(lib cell)
  let((master)
    master=dbOpenCellViewByType(lib cell "symbol" "schematicSymbol" "r")
    unless(master error("Missing installed symbol %s/%s\n" lib cell))
    master
  )
)

procedure(laOaStub(cv inst pinName netName)
  let((term fig start pos0 dy middle finish points wires labelPos justify)
    term=dbFindTermByName(inst~>master pinName)
    unless(term && term~>pins error("Missing symbol pin %s.%s\n" inst~>name pinName))
    fig=car(term~>pins)~>fig
    start=dbTransformPoint(centerBox(fig~>bBox) inst~>transform)
    pos0=inst~>xy
    dy=yCoord(start)-yCoord(pos0)
    cond(
      (equal(pinName "G")
        finish=list(xCoord(start)-0.375 yCoord(start))
        points=list(start finish)
        labelPos=list(xCoord(finish)-0.03125 yCoord(finish)+0.03125)
        justify="lowerRight"
      )
      (equal(pinName "B")
        finish=list(xCoord(pos0)+1.0 yCoord(start))
        points=list(start finish)
        labelPos=list(xCoord(finish)+0.03125 yCoord(finish))
        justify="centerLeft"
      )
      (member(pinName list("D" "S"))
        middle=list(xCoord(start) yCoord(start)+if(dy>=0 then 0.375 else -0.375))
        finish=list(xCoord(pos0)+1.0 yCoord(middle))
        points=list(start middle finish)
        labelPos=list(xCoord(finish)+0.03125 yCoord(finish)+0.03125)
        justify="lowerLeft"
      )
      (t
        finish=list(xCoord(start)+if(member(pinName list("PLUS" "NC+" "NC-")) then -0.5 else 0.5) yCoord(start))
        points=list(start finish)
        if(member(pinName list("PLUS" "NC+" "NC-")) then
          labelPos=list(xCoord(finish)-0.03125 yCoord(finish)+0.03125)
          justify="lowerRight"
        else
          labelPos=list(xCoord(finish)+0.03125 yCoord(finish)+0.03125)
          justify="lowerLeft"
        )
      )
    )
    wires=schCreateWire(cv "draw" "full" points 0.0625 0.0625 0)
    unless(wires error("Wire creation failed %s.%s\n" inst~>name pinName))
    unless(schCreateWireLabel(cv car(wires) labelPos netName justify "R0" "stick" 0.0625 nil)
      error("Wire labeling failed %s.%s\n" inst~>name pinName)
    )
  )
)

procedure(laOaSaveCdf(inst param)
  cond(
    (stringp(param->value) dbReplaceProp(inst param->name "string" param->value))
    (fixp(param->value) dbReplaceProp(inst param->name "int" param->value))
    (numberp(param->value) dbReplaceProp(inst param->name "float" param->value))
    (eq(param->value t) dbReplaceProp(inst param->name "boolean" t))
    (t error("Unsupported effective CDF value %s.%s = %L\n" inst~>name param->name param->value))
  )
)

procedure(laOaCdfCallbacks(inst callbacks mode out)
  let((sourceCdf sourceP cdfgData cdfgForm p initProc callbackResult)
    sourceCdf=cdfGetInstCDF(inst)
    unless(sourceCdf error("No effective CDF for %s\n" inst~>name))
    cdfgForm=nil
    if(member(mode list("instance" "instance_init")) then
      cdfgData=sourceCdf
      unless(eq(cdfgData->id inst) error("CDF id is not the real instance\n"))
      when(equal(mode "instance_init")
        initProc=cdfgData->formInitProc
        unless(stringp(initProc) && !blankstrp(initProc) error("Missing installed formInitProc\n"))
        callbackResult=errsetstring(strcat(initProc "(cdfgData)") t)
        unless(callbackResult error("Foundry formInitProc failed %s\n" inst~>name))
      )
    else
      cdfgData=cdfGetCellCDF(ddGetObj(inst~>libName inst~>cellName))
      unless(cdfgData error("No cell CDF for %s\n" inst~>name))
      foreach(p cdfgData->parameters
        sourceP=cdfFindParamByName(sourceCdf p->name)
        when(sourceP p->value=sourceP->value)
      )
    )
    foreach(pair callbacks
      p=cdfFindParamByName(cdfgData car(pair))
      unless(p && p->callback error("Installed callback missing %s.%s\n" inst~>name car(pair)))
      p->value=cadr(pair)
      fprintf(out "# CALLBACK %s %s requested=%L\n" inst~>name car(pair) cadr(pair))
      callbackResult=errsetstring(p->callback t)
      unless(callbackResult error("Foundry callback failed %s.%s\n" inst~>name car(pair)))
    )
    foreach(p cdfgData->parameters
      when(p && p->value!=nil
        fprintf(out "%s\t%s\t%L\n" inst~>name p->name p->value)
        laOaSaveCdf(inst p)
      )
    )
    t
  )
)


; New layout-only native PCell probe. No source CDF updates, schematic writes,
; routing, simulation, or rule suppression. All public PCell parameters come
; directly from the saved qualified source instance's effective CDF.
procedure(laR3Typed(value valueType name)
  cond(
    (equal(valueType "string")
      cond((stringp(value) value) (fixp(value) sprintf(nil "%d" value))
           (numberp(value) sprintf(nil "%.16g" value))
           (t error("Unsupported string parameter %s=%L\n" name value))))
    (member(valueType list("int" "integer"))
      cond((fixp(value) value)
           (stringp(value) let((n) n=cdfParseFloatString(value)
             unless(numberp(n) && n==round(n) error("Invalid integer %s\n" name)) round(n)))
           (t error("Unsupported integer parameter %s\n" name))))
    (member(valueType list("float" "double"))
      cond((numberp(value) value)
           (stringp(value) let((n) n=cdfParseFloatString(value)
             unless(numberp(n) error("Invalid numeric %s\n" name)) n))
           (t error("Unsupported numeric parameter %s\n" name))))
    (equal(valueType "boolean")
      cond((value==t || equal(value "TRUE") || equal(value "true") t)
           (value==nil || equal(value "FALSE") || equal(value "false") nil)
           (t error("Invalid boolean %s=%L\n" name value))))
    (t error("Unsupported public PCell type %s=%s\n" name valueType))
  )
)

procedure(laR3SourceSnapshot(inst)
  let((cdf values)
    cdf=cdfGetInstCDF(inst)
    foreach(p cdf->parameters values=cons(list(p->name p->value) values))
    reverse(values)
  )
)

procedure(laR3Params(master source audit)
  let((cdf cp params typed)
    cdf=cdfGetInstCDF(source)
    unless(master~>parameters~>value error("Not a native parametric master\n"))
    foreach(p master~>parameters~>value
      cp=cdfFindParamByName(cdf p~>name)
      if(cp then
        typed=laR3Typed(cp->value p~>valueType p~>name)
        fprintf(audit "SOURCE_PARAM\t%s\t%s\t%s\t%L\t%L\n"
          source~>name p~>name p~>valueType cp->value typed)
      else
        unless(equal(source~>cellName "rm1w") &&
          !member(p~>name list("l" "w" "m" "multi" "segments" "connection"))
          error("Missing electrical source CDF %s.%s\n" source~>name p~>name))
        typed=laR3Typed(p~>value p~>valueType p~>name)
        fprintf(audit "NATIVE_DEFAULT_PARAM\t%s\t%s\t%s\t%L\t%L\n"
          source~>name p~>name p~>valueType p~>value typed)
      )
      params=cons(list(p~>name p~>valueType typed) params)
    )
    reverse(params)
  )
)

procedure(laR3CheckParams(inst params audit)
  let((actual actualTyped hit count)
    count=0
    foreach(row params
      hit=car(setof(p inst~>master~>parameters~>value equal(p~>name car(row))))
      unless(hit error("Generated PCell has no %s\n" car(row)))
      actual=hit~>value
      actualTyped=laR3Typed(actual cadr(row) car(row))
      unless(equal(actualTyped caddr(row))
        error("Native PCell parameter mismatch %s.%s expected=%L actual=%L\n"
          inst~>name car(row) caddr(row) actual))
      fprintf(audit "PARAM_MATCH\t%s\t%s\t%L\t%L\n" inst~>name car(row) actual actualTyped)
      count=count+1
    )
    count
  )
)

procedure(laR3Geometry(inst audit phase)
  let((counts pinCount shapeCount layer)
    counts=makeTable('laR3Layers 0)
    pinCount=0
    fprintf(audit "INSTANCE\t%s\t%s\t%s\t%L\t%L\t%d\t%d\n"
      phase inst~>name inst~>master~>cellName inst~>bBox inst~>master~>bBox
      length(inst~>master~>terminals) length(inst~>master~>instances))
    foreach(fig inst~>master~>shapes
      layer=car(fig~>lpp)
      counts[fig~>lpp]=counts[fig~>lpp]+1
      when(equal(layer "marker") || equal(cadr(fig~>lpp) "error")
        error("Native PCell marker/error %s %L\n" inst~>name fig~>bBox))
      when(member(layer list("OD" "PO" "PP" "NP" "NW" "DNW" "SR_DPO" "LVT" "CO" "RPO" "RM1"))
        fprintf(audit "DEVICE_MASK\t%s\t%s\t%L\t%L\n"
          phase inst~>name fig~>lpp fig~>bBox))
      when(equal(fig~>objType "label")
        fprintf(audit "NATIVE_LABEL\t%s\t%s\t%L\t%L\n"
          phase inst~>name fig~>lpp fig~>theLabel))
    )
    foreach(key counts
      fprintf(audit "LAYER_COUNT\t%s\t%s\t%L\t%d\n" phase inst~>name key counts[key]))
    foreach(term inst~>master~>terminals
      fprintf(audit "TERMINAL\t%s\t%s\t%s\t%d\n" phase inst~>name term~>name length(term~>pins))
      foreach(pin term~>pins foreach(fig pin~>figs
        pinCount=pinCount+1
        fprintf(audit "PIN\t%s\t%s\t%s\t%L\t%L\t%L\n"
          phase inst~>name term~>name fig~>lpp fig~>bBox dbTransformBBox(fig~>bBox inst~>transform))))
    )
    unless(pinCount>0 error("Native PCell lacks landing figures %s\n" inst~>name))
    fprintf(audit "GEOMETRY_DONE\t%s\t%s\t%d\n" phase inst~>name pinCount)
    t
  )
)


; Designer-owned routing helpers. Native PCell/CDF utilities are prepended
; by prepare_stage.py into native_helpers.il. All coordinates are um.
procedure(laR3Center(bb)
  list((xCoord(car(bb))+xCoord(cadr(bb)))/2.0
       (yCoord(car(bb))+yCoord(cadr(bb)))/2.0)
)
procedure(laR3Rect(ctx net layer bb)
  let((fig)
    unless(xCoord(cadr(bb))>xCoord(car(bb)) && yCoord(cadr(bb))>yCoord(car(bb))
      error("Invalid route rectangle %s %L\n" layer bb))
    fig=dbCreateRect(ctx["cv"] list(layer "drawing") bb)
    unless(fig error("Cannot create %s rectangle\n" layer))
    dbAddFigToNet(fig net)
    fprintf(ctx["audit"] "ROUTE_RECT\t%s\t%s\t%L\n" net~>name layer bb)
    fig
  )
)
procedure(laR3Pad(ctx net layer xy width height)
  laR3Rect(ctx net layer list(list(xCoord(xy)-width/2.0 yCoord(xy)-height/2.0)
                                list(xCoord(xy)+width/2.0 yCoord(xy)+height/2.0)))
)
procedure(laR3Segment(ctx net layer a b width)
  unless(abs(xCoord(a)-xCoord(b))<.000001 || abs(yCoord(a)-yCoord(b))<.000001
    error("Manhattan route required %s %L %L\n" net~>name a b))
  laR3Rect(ctx net layer list(
    list(min(xCoord(a) xCoord(b))-width/2.0 min(yCoord(a) yCoord(b))-width/2.0)
    list(max(xCoord(a) xCoord(b))+width/2.0 max(yCoord(a) yCoord(b))+width/2.0)))
)
procedure(laR3Via(ctx net name xy @optional overrides)
  let((vd via)
    vd=techFindViaDefByName(techGetTechFile(ctx["cv"]) name)
    unless(vd error("Missing native via %s\n" name))
    via=dbCreateVia(ctx["cv"] vd xy "R0" overrides)
    unless(via error("Native via creation failed %s\n" name))
    dbAddFigToNet(via net)
    fprintf(ctx["audit"] "ROUTE_VIA\t%s\t%s\t%L\t%L\t%L\n"
      net~>name name xy via~>bBox via~>viaHeader~>overrideParams)
    via
  )
)
procedure(laR3Port(ctx net layer xy @optional (label nil))
  let((fig term)
    fig=laR3Pad(ctx net layer xy .30 .30)
    term=dbCreateTerm(net net~>name "inputOutput")
    unless(term && dbCreatePin(net fig) error("Cannot create OA port %s\n" net~>name))
    when(label dbCreateLabel(ctx["cv"] list(layer "pin") xy net~>name "centerCenter" "R0" "roman" .12))
    fprintf(ctx["audit"] "PORT\t%s\t%s\t%L\t%L\tLABEL=%L\n"
      net~>name layer xy fig~>bBox label)
    term
  )
)
procedure(laR3Native(ctx source name xy orient)
  let((master params inst)
    master=dbOpenCellViewByType(source~>libName source~>cellName "layout" "maskLayout" "r")
    unless(master error("Native layout master absent %s\n" source~>cellName))
    params=laR3Params(master source ctx["audit"])
    inst=dbCreateParamInst(ctx["cv"] master name xy orient 1 params)
    unless(inst error("Native PCell creation failed %s\n" name))
    laR3CheckParams(inst params ctx["audit"])
    laR3Geometry(inst ctx["audit"] "STAGE")
    dbClose(master)
    inst
  )
)
procedure(laR3Bind(inst mapping)
  let((base pair)
    foreach(term inst~>master~>terminals
      base=car(parseString(term~>name "_"))
      pair=assoc(base mapping)
      unless(pair error("No native pin mapping %s.%s\n" inst~>name term~>name))
      unless(dbCreateInstTerm(cadr(pair) inst term) error("Native terminal binding failed\n")))
    t
  )
)
procedure(laR3MetalPins(inst termName layer)
  let((term answer)
    term=dbFindTermByName(inst~>master termName)
    unless(term error("Native terminal absent %s.%s\n" inst~>name termName))
    foreach(pin term~>pins foreach(fig pin~>figs
      when(equal(car(fig~>lpp) layer)
        answer=cons(dbTransformBBox(fig~>bBox inst~>transform) answer))))
    reverse(answer)
  )
)
procedure(laR3Mos(ctx inst d s g b)
  let((origin x y gateBoxes gateX gateLow gateHigh row lo hi found bb gxMin gxMax gateY net count overrides)
    unless(equal(inst~>orient "R0") error("First stage adapter is qualified only for R0\n"))
    origin=inst~>xy x=xCoord(origin) y=yCoord(origin)
    laR3Bind(inst list(list("D" d) list("S" s) list("G" g) list("B" b)))
    gateBoxes=laR3MetalPins(inst "G" "M2")
    unless(length(gateBoxes)==2 error("Both native M2 gate rows required\n"))
    gateLow=min(yCoord(laR3Center(car(gateBoxes))) yCoord(laR3Center(cadr(gateBoxes))))
    gateHigh=max(yCoord(laR3Center(car(gateBoxes))) yCoord(laR3Center(cadr(gateBoxes))))
    ; Merge the genuine native M1 gate contact pads at each native row.
    foreach(row gateBoxes
      lo=yCoord(car(row)) hi=yCoord(cadr(row)) gxMin=1e9 gxMax=-1e9
      foreach(fig inst~>master~>shapes
        when(equal(fig~>lpp list("M1" "drawing"))
          bb=dbTransformBBox(fig~>bBox inst~>transform)
          when(abs(yCoord(car(bb))-lo)<.000001 && abs(yCoord(cadr(bb))-hi)<.000001
            gxMin=min(gxMin xCoord(car(bb))) gxMax=max(gxMax xCoord(cadr(bb))))))
      unless(gxMax>gxMin error("Native gate M1 contact row absent\n"))
      laR3Rect(ctx g "M1" list(list(gxMin lo) list(gxMax hi)))
    )
    ; All 11 D and 12 S M1 bars receive native two-cut access. The public
    ; asymmetric M1 enclosure is foundry VIA1 EN.2/.3/.14/.15 and combined
    ; EN.3/.5/.6/.7 alternative: two opposite >=.03, all >=.01.
    count=0
    foreach(term inst~>master~>terminals
      when(member(car(parseString(term~>name "_")) list("D" "S"))
        net=if(equal(car(parseString(term~>name "_")) "D") d s)
        gateY=y+if(equal(net d) .5 1.5)
        foreach(pin term~>pins foreach(fig pin~>figs
          when(equal(fig~>lpp list("M1" "drawing"))
            bb=dbTransformBBox(fig~>bBox inst~>transform)
            gateX=xCoord(laR3Center(bb))
            overrides=list(list("cutRows" 6) list("cutColumns" 1) list("layer1Enc" list(.01 .03)))
            laR3Via(ctx net "M2_M1" list(gateX gateY) overrides)
            laR3Pad(ctx net "M2" list(gateX gateY) .14 .78)
            laR3Via(ctx net "M3_M2" list(gateX gateY) list(list("cutRows" 6) list("cutColumns" 1)))
            when(equal(net d)
              laR3Pad(ctx net "M3" list(gateX gateY) .14 .78)
              laR3Via(ctx net "M4_M3" list(gateX gateY) list(list("cutRows" 6) list("cutColumns" 1))))
            count=count+1))))
    )
    unless(count==23 error("All-finger landing count differs %d\n" count))
    laR3Segment(ctx d "M4" list(x+.08 y+.5) list(x+2.68 y+.5) .80)
    laR3Segment(ctx s "M3" list(x-.05 y+1.5) list(x+2.81 y+1.5) .80)
    ; Join both M2 gate rows outside the SD access region on the left.
    gateX=x-.40
    foreach(row gateBoxes
      gateY=yCoord(laR3Center(row))
      laR3Segment(ctx g "M2" list(gateX gateY) list(xCoord(car(row))+.06 gateY) .14))
    laR3Segment(ctx g "M2" list(gateX gateLow) list(gateX gateHigh) .14)
    fprintf(ctx["audit"] "MOS_ALL_FINGERS\t%s\tD=11\tS=12\tLANDINGS=23\tG_BOTH_JOINED=t\n" inst~>name)
    t
  )
)
procedure(laR3Load(ctx inst plus minus)
  let((boxes xmin xmax ymin ymax x center count result net)
    laR3Bind(inst list(list("PLUS" plus) list("MINUS" minus)))
    result=nil
    foreach(termName list("PLUS" "MINUS")
      net=if(equal(termName "PLUS") plus minus)
      boxes=laR3MetalPins(inst termName "M1")
      unless(length(boxes)==12 error("Native parallel12 bank requires all12 rail pins\n"))
      ymin=1e9 ymax=-1e9 count=0
      x=xCoord(laR3Center(car(boxes)))
      foreach(bb boxes
        unless(abs(xCoord(laR3Center(bb))-x)<.000001 error("Non-collinear native rail\n"))
        center=laR3Center(bb)
        ymin=min(ymin yCoord(car(bb))) ymax=max(ymax yCoord(cadr(bb)))
        laR3Via(ctx net "M2_M1" center list(list("cutRows" 6) list("cutColumns" 1)))
        laR3Pad(ctx net "M1" center .14 .78)
        count=count+1)
      laR3Rect(ctx net "M2" list(list(x-.10 ymin) list(x+.10 ymax)))
      result=cons(list(termName x ymin ymax) result)
      fprintf(ctx["audit"] "LOAD_RAIL\t%s\t%s\tX=%.12g\tYMIN=%.12g\tYMAX=%.12g\tTAPS=%d\n"
        inst~>name termName x ymin ymax count))
    reverse(result)
  )
)
procedure(laR3NativeTap(ctx tapMaster centerX originY net)
  let((term left bbox sourceCenter dx dy trans copied count counts region)
    term=dbFindTermByName(tapMaster "B")
    foreach(pin term~>pins foreach(fig pin~>figs
      when(equal(fig~>lpp list("M1" "drawing")) && xCoord(cadr(fig~>bBox))<0
        left=fig~>bBox)))
    unless(left error("Native Detached p+ left tap metal absent\n"))
    sourceCenter=laR3Center(left)
    dx=centerX-xCoord(sourceCenter) dy=originY-yCoord(car(left))
    trans=list(list(dx dy) "R0" 1.0)
    region=list(list(xCoord(car(left))-.10 yCoord(car(left))-.20)
                list(xCoord(cadr(left))+.10 yCoord(cadr(left))+.20))
    counts=makeTable('laR3TapCounts 0) count=0
    foreach(fig tapMaster~>shapes
      bbox=fig~>bBox
      when(member(car(fig~>lpp) list("OD" "PP" "CO" "M1")) &&
        xCoord(car(bbox))>=xCoord(car(region)) && xCoord(cadr(bbox))<=xCoord(cadr(region)) &&
        yCoord(car(bbox))>=yCoord(car(region)) && yCoord(cadr(bbox))<=yCoord(cadr(region))
        copied=dbCopyFig(fig ctx["cv"] trans)
        unless(copied error("Native complete tap mask copy failed\n"))
        when(equal(car(fig~>lpp) "M1") dbAddFigToNet(copied net))
        counts[car(fig~>lpp)]=counts[car(fig~>lpp)]+1 count=count+1
        fprintf(ctx["audit"] "NATIVE_TAP_MASK\t%L\t%L\n" copied~>lpp copied~>bBox)))
    unless(counts["OD"]>0 && counts["PP"]>0 && counts["CO"]>0 && counts["M1"]>0
      error("Incomplete copied native p+ tap mask group\n"))
    laR3Via(ctx net "M2_M1" list(centerX originY+1.0) list(list("cutRows" 4) list("cutColumns" 1)))
    laR3Pad(ctx net "M2" list(centerX originY+1.0) .14 .52)
    laR3Via(ctx net "M3_M2" list(centerX originY+1.0) list(list("cutRows" 4) list("cutColumns" 1)))
    fprintf(ctx["audit"] "NATIVE_TAP_COMPLETE\tX=%.12g\tORIGINY=%.12g\tMASKS=%d\n" centerX originY count)
    count
  )
)
procedure(laR3Tail(ctx inst plus minus)
  let((bbox bb xy pad edge xmin xmax ymin ymax result net overrides)
    laR3Bind(inst list(list("PLUS" plus) list("MINUS" minus)))
    bbox=inst~>bBox xmin=xCoord(car(bbox)) xmax=xCoord(cadr(bbox))
    result=nil
    foreach(termName list("MINUS" "PLUS")
      net=if(equal(termName "PLUS") plus minus)
      bb=car(laR3MetalPins(inst termName "M1"))
      unless(bb error("Native rm1w terminal strip absent\n"))
      ymin=yCoord(car(bb)) ymax=yCoord(cadr(bb))
      if(equal(termName "MINUS") then
        edge=xCoord(cadr(bb))
        xy=list(xmin-.20 (ymin+ymax)/2.0)
        pad=list(list(xmin-.40 ymin) list(edge ymax))
      else
        edge=xCoord(car(bb))
        xy=list(xmax+.20 (ymin+ymax)/2.0)
        pad=list(list(edge ymin) list(xmax+.40 ymax)))
      ; Outward-only pad overlaps the native5nm terminal strip, never the
      ; marked resistor body. Vias are beyond the body boundary.
      laR3Rect(ctx net "M1" pad)
      overrides=list(list("cutRows" 4) list("cutColumns" 2))
      laR3Via(ctx net "M2_M1" xy overrides)
      laR3Pad(ctx net "M2" xy .26 .52)
      laR3Via(ctx net "M3_M2" xy overrides)
      laR3Pad(ctx net "M3" xy .26 .52)
      result=cons(list(termName xy) result)
      fprintf(ctx["audit"] "TAIL_OUTWARD_ACCESS\t%s\t%s\t%L\t%L\n"
        inst~>name termName xy pad))
    reverse(result)
  )
)

; Isolated source/geometry inventory only. No simulation, full amplifier, or
; existing source modifications. Root explicitly owns launch and qualification.
procedure(laR5CopySource(inst source)
  let((cdf)
    cdf=cdfGetInstCDF(source)
    foreach(p cdf->parameters
      if(p->value!=nil then laOaSaveCdf(inst p)
      else when(equal(p->type "boolean") dbReplaceProp(inst p->name "boolean" nil))))
    unless(equal(laR3SourceSnapshot(inst) laR3SourceSnapshot(source))
      error("Initial own-probe CDF copy differs from saved source\n"))
    t)
)
procedure(laR5SetPassiveSegments(inst segments audit)
  let((cdf cp mode)
    cdf=cdfGetInstCDF(inst)
    foreach(key list("ResCalc" "segments" "connection" "prl" "multi" "l" "w")
      cp=cdfFindParamByName(cdf key)
      unless(cp error("Installed resistor CDF field absent %s\n" key))
      fprintf(audit "PASSIVE_CDF_METADATA\t%s\t%s\tPROMPT=%L\tTYPE=%L\tCHOICES=%L\tCALLBACK_PRESENT=%L\n"
        inst~>name key cp->prompt cp->type cp->choices cp->callback!=nil))
    cp=cdfFindParamByName(cdf "ResCalc")
    ; Apply this mode only if it is an actual installed native choice.
    ; This is a guard, not an invented PDK option. Other native naming stops
    ; here with metadata available rather than guessing a control value.
    unless(member("l_&_w" cp->choices)
      error("Native geometry-preserving ResCalc choice not established: %L\n" cp->choices))
    mode="l_&_w"
    laOaCdfCallbacks(inst list(list("ResCalc" mode) list("connection" "Parallel")
      list("segments" segments) list("w" "1u") list("l" "1.035u")) "instance" audit)
    t)
)

; Designer-owned NF44 diagnostic layout. All dimensions in um.
; Actual DRC/LVS/RCC and current qualification are required; no signoff implied.
procedure(laR5SmallStack(ctx net xy first last)
  let((names)
    names=list("M4_M3" "M5_M4" "M6_M5")
    foreach(name names
      laR3Via(ctx net name xy list(list("cutRows" 2) list("cutColumns" 2))))
    foreach(layer list("M3" "M4" "M5" "M6") laR3Pad(ctx net layer xy .30 .30))
    t)
)
procedure(laR5PlaneStack(ctx net xy)
  ; Native .05um cuts, .08um edge spacing; 8x8 total cut span .96um.
  ; Native 1.02um enclosures remain within existing M3..M6 source planes.
  ; This helper is used only for plane pickups, never body-tap stacks.
  foreach(name list("M4_M3" "M5_M4" "M6_M5")
    laR3Via(ctx net name xy list(list("cutRows" 8) list("cutColumns" 8)
      list("cutSpacing" list(.08 .08)))))
  fprintf(ctx["audit"] "R5_SOURCE_PLANE_8X8\t%L\tACTUAL_DRC_EM_PENDING\n" xy)
  t
)
procedure(laR5Mos44(ctx inst d s g b)
  let((x y gateBoxes lo hi gxMin gxMax bb gateY net xpin count rows over dPickups)
    unless(equal(inst~>orient "R0") error("NF44 adapter requires source R0 orientation\n"))
    x=xCoord(inst~>xy) y=yCoord(inst~>xy)
    laR3Bind(inst list(list("D" d) list("S" s) list("G" g) list("B" b)))
    gateBoxes=laR3MetalPins(inst "G" "M2")
    unless(length(gateBoxes)==2 error("Both source gate contact rows required\n"))
    foreach(row gateBoxes
      lo=yCoord(car(row)) hi=yCoord(cadr(row)) gxMin=1e9 gxMax=-1e9
      foreach(fig inst~>master~>shapes
        when(equal(fig~>lpp list("M1" "drawing"))
          bb=dbTransformBBox(fig~>bBox inst~>transform)
          when(abs(yCoord(car(bb))-lo)<1e-6 && abs(yCoord(cadr(bb))-hi)<1e-6
            gxMin=min(gxMin xCoord(car(bb))) gxMax=max(gxMax xCoord(cadr(bb))))))
      unless(gxMax>gxMin error("Native gate M1 contact row absent\n"))
      laR3Rect(ctx g "M1" list(list(gxMin lo) list(gxMax hi)))
      gateY=yCoord(laR3Center(row))
      laR3Segment(ctx g "M2" list(x-1.0 gateY) list(xCoord(car(row))+.06 gateY) .14))
    laR3Segment(ctx g "M2" list(x-1.0 y-.115) list(x-1.0 y+1.115) .14)
    count=0 dPickups=list(.08 1.90 3.72 5.54)
    foreach(term inst~>master~>terminals
      when(member(car(parseString(term~>name "_")) list("D" "S"))
        net=if(equal(car(parseString(term~>name "_")) "D") d s)
        gateY=y+if(equal(net d) .23 .77)
        foreach(pin term~>pins foreach(fig pin~>figs
          when(equal(fig~>lpp list("M1" "drawing"))
            bb=dbTransformBBox(fig~>bBox inst~>transform)
            unless(abs(yCoord(car(bb))-y)<1e-6 && abs(yCoord(cadr(bb))-(y+1.0))<1e-6
              error("NF44 adapter only supports actual active bar height1um\n"))
            xpin=xCoord(laR3Center(bb))
            ; Actual v2 G.4:M1i markers: fill the narrow native bar's
            ; short endpoint jogs with uniform .07um M1 across active height.
            laR3Rect(ctx net "M1" list(list(xpin-.035 y) list(xpin+.035 y+1.0)))
            over=list(list("cutRows" 3) list("cutColumns" 1) list("cutSpacing" list(.08 .08)))
            laR3Via(ctx net "M2_M1" list(xpin gateY)
              append(over list(list("layer1Enc" list(.01 .03)))))
            laR3Via(ctx net "M3_M2" list(xpin gateY) over)
            laR3Pad(ctx net "M2" list(xpin gateY) .14 .37)
            laR3Pad(ctx net "M3" list(xpin gateY) .14 .37)
            if(equal(net d) then
              foreach(name list("M4_M3" "M5_M4")
                laR3Via(ctx net name list(xpin gateY) over))
              if(exists(dx dPickups abs((xpin-x)-dx)<1e-6) then
                ; Four native upper cuts only at the wide M6 pickup landing.
                ; Replace the one-column array here; never overlap two arrays.
                laR3Via(ctx net "M6_M5" list(xpin gateY)
                  list(list("cutRows" 2) list("cutColumns" 2)))
                laR3Pad(ctx net "M5" list(xpin gateY) .30 .30)
              else laR3Via(ctx net "M6_M5" list(xpin gateY) over))
              foreach(layer list("M4" "M5" "M6") laR3Pad(ctx net layer list(xpin gateY) .14 .37))
            else
              laR3Segment(ctx net "M3" list(xpin gateY) list(xpin y+4.0) .14))
            count=count+1))))
    )
    unless(count==45 error("All NF44 SD fingers required, got%d\n" count))
    ; Parallel lower-level drain collectors. Current capacity remains unqualified.
    foreach(layer list("M4" "M5" "M6")
      laR3Segment(ctx d layer list(x-.65 y+.23) list(x+6.45 y+.23) .40))
    foreach(dx list(-.65 6.45)
      laR3Pad(ctx d "M6" list(x+dx y+.23) .60 .80)
      laR3Via(ctx d "M7_M6" list(x+dx y+.23))
      laR3Pad(ctx d "M7" list(x+dx y+.23) .90 .80))
    ; Actual v1 current-path review: add a thick-metal drain bridge now that
    ; the source upper plane is at y4.0, safely above this y.23 bridge.
    foreach(dx dPickups
      laR3Pad(ctx d "M6" list(x+dx y+.23) .60 .80)
      laR3Via(ctx d "M7_M6" list(x+dx y+.23))
      laR3Pad(ctx d "M7" list(x+dx y+.23) .90 .80))
    laR3Segment(ctx d "M7" list(x-.65 y+.23) list(x+6.45 y+.23) .90)
    fprintf(ctx["audit"] "R5_DRAIN_M7_BRIDGE\t%s\tWIDTH.90\tPICKUPS4\tCURRENT_UNQUALIFIED\n" inst~>name)
    ; Distributed ground plane is above the finger contacts, preserving gate
    ; access outside its left boundary. No single thin full-current source wire.
    foreach(layer list("M3" "M4" "M5" "M6")
      laR3Rect(ctx s layer list(list(x-.15 y+2.5) list(x+5.82 y+5.5))))
    foreach(dx list(1.1 2.9 4.7)
      laR5PlaneStack(ctx s list(x+dx y+4.0))
      laR3Pad(ctx s "M6" list(x+dx y+4.0) .60 .80)
      laR3Via(ctx s "M7_M6" list(x+dx y+4.0))
      laR3Pad(ctx s "M7" list(x+dx y+4.0) 1.60 1.60)
      laR3Via(ctx s "M8_M7" list(x+dx y+4.0) list(list("cutRows" 2) list("cutColumns" 2)))
      laR3Pad(ctx s "M8" list(x+dx y+4.0) 3.0 3.0))
    laR3Segment(ctx s "M7" list(x+1.1 y+4.0) list(x+4.7 y+4.0) 1.60)
    fprintf(ctx["audit"] "R5_MOS_CONTACTS\t%s\tD22_S23\tALL45_CONTACTED\tCUTROWS3\tEM_UNQUALIFIED\n" inst~>name)
    t)
)
procedure(laR5FoldHalf(ctx inst vdd out collectorX)
  let((boxes firstY lastY center net count x)
    laR3Bind(inst list(list("PLUS" vdd) list("MINUS" out)))
    foreach(termName list("PLUS" "MINUS")
      net=if(equal(termName "PLUS") vdd out)
      boxes=laR3MetalPins(inst termName "M1")
      unless(length(boxes)==6 error("Native halfbank requires exactly6 pins\n"))
      boxes=sort(boxes lambda((a b) yCoord(laR3Center(a))<yCoord(laR3Center(b))))
      firstY=yCoord(car(car(boxes))) lastY=yCoord(cadr(car(last(boxes)))) count=0
      x=xCoord(laR3Center(car(boxes)))
      foreach(bb boxes
        center=laR3Center(bb)
        unless(abs(xCoord(center)-x)<1e-6 error("Native halfbank rail not collinear\n"))
        laR3Via(ctx net "M2_M1" center list(list("cutRows" 6) list("cutColumns" 1)))
        laR3Pad(ctx net "M1" center .14 .78)
        foreach(name list("M3_M2" "M4_M3" "M5_M4" "M6_M5")
          laR3Via(ctx net name center list(list("cutRows" 6) list("cutColumns" 1))))
        foreach(layer list("M3" "M4" "M5") laR3Pad(ctx net layer center .14 .78))
        laR3Pad(ctx net "M6" center .60 .80)
        if(equal(termName "MINUS") then
          laR3Segment(ctx net "M6" center list(collectorX yCoord(center)) .60)
          laR3Via(ctx net "M7_M6" list(collectorX yCoord(center)))
          laR3Pad(ctx net "M7" list(collectorX yCoord(center)) .90 .80)
        else
          laR3Via(ctx net "M7_M6" center)
          laR3Pad(ctx net "M7" center .60 .96)
          when(count>=2
            laR3Via(ctx net "M8_M7" center list(list("cutRows" 1) list("cutColumns" 2)))
            laR3Pad(ctx net "M7" center 1.60 .80)))
        count=count+1)
      laR3Rect(ctx net "M2" list(list(x-.10 firstY) list(x+.10 lastY)))
      if(equal(termName "MINUS") then
        laR3Segment(ctx out "M7" list(collectorX .23) list(collectorX yCoord(laR3Center(car(last(boxes))))) .90)
      else
        laR3Segment(ctx vdd "M7" list(x yCoord(laR3Center(car(boxes)))) list(x yCoord(laR3Center(car(last(boxes))))) .60)
        laR3Segment(ctx vdd "M8" list(x yCoord(laR3Center(nth(2 boxes)))) list(x 17.5) 2.0))
      fprintf(ctx["audit"] "R5_HALF_BANK\t%s\t%s\tCONTACTS6\tCOLLECTORX=%.9g\n" inst~>name termName collectorX))
    t)
)
procedure(laR5OutputAccess(ctx net collectorX portX)
  ; Place down-stack above the source plane, with clearance to its wide edges.
  let((xy)
    xy=list(collectorX 6.5)
    laR3Via(ctx net "M7_M6" xy)
    laR3Pad(ctx net "M6" xy .60 .80)
    laR3Pad(ctx net "M7" xy .90 .80)
    foreach(name list("M6_M5" "M5_M4" "M4_M3")
      laR3Via(ctx net name xy list(list("cutRows" 4) list("cutColumns" 4)
        list("cutSpacing" list(.08 .08)))))
    foreach(layer list("M3" "M4" "M5") laR3Pad(ctx net layer xy .54 .54))
    laR3Segment(ctx net "M6" xy list(collectorX 7.335) .60)
    laR3Segment(ctx net "M3" xy list(portX 6.5) .30)
    t)
)
