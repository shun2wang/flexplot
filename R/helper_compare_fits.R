get_re = function(model) {
  if (!(class(model)[1] %in% c("lmerMod", "glmerMod"))) {
    return(NULL)
  }
  text_formula = paste0(formula(model))[3]
  re = gsub(".* | [.+]", "\\1", text_formula)
  re = gsub(")", "", re)
  return(re)
}

whats_model2 = function(model1,model2=NULL) {
  if (is.null(model2)){
    return(model1)
  } 
  return(model2)
}

# function that extracts variables from cforest model
get_cforest_variables = function(model, return.type=c("all", "predictors", "response")) {
  
  return.type = match.arg(return.type)
  
  ## get all variables 
  vars = attr(model, "data")@formula
  
  if (return.type == "all") {
    response = unlist(strsplit(as.character(vars$response)[2], " + ", fixed=T))
    input = unlist(strsplit(as.character(vars$input)[2], " + ", fixed=T))
    all_vars = c(response, input)
    return(all_vars)
  }
  
  if (return.type == "predictors") {
    input = unlist(strsplit(as.character(vars$input)[2], " + ", fixed=T))
    return(input)
  }
  
  response = unlist(strsplit(as.character(vars$response)[2], " + ", fixed=T))
  return(response)
}

get_terms = function(model) {
  
  model.type = class(model)[1]
  
  #### extract the terms from each MODEL
  if (model.type == "RandomForest") {
    predictors = get_cforest_variables(model, "predictors");
    response = get_cforest_variables(model, "response");
    return(list(predictors = predictors, response=response))
  } 
    
  form = formula(model) 
  predictors=all.vars(form)[-1]  
  response = all.vars(form)[1]
  return(list(predictors = predictors, response=response))
}

check_missing = function(model1, model2=NULL, data, variables) {

  ### if they haven't supplied model 2, no need to check
  if (is.null(model2)) return(data)
  
  n1 = get_model_n(model1)
  n2 = get_model_n(model2)
  
  if (n1<nrow(data) | n2<nrow(data)){
    data = na.omit(data[,variables])
  }
  
  return(data)
}

get_model_n = function(model) {

  mod_class = class(model)[1]
  if (mod_class == "RandomForest") return(attr(model, "responses")@nobs)
  if (mod_class == "randomForest.formula") return(length(model$predicted))
  if (mod_class == "lmerMod" | mod_class == "glmerMod") return(nobs(model))
  if (mod_class == "rpart") return(length(model$y))
  
  return(nrow(model$model))
  
}

### function to generate prediction matrix spanning the range of the data
generate_predictors = function(data, predictors, model_terms, num_points, mod_class) {

  #### create random column just to make the applies work (yeah, it's hacky, but it works)
  data$reject = 1:nrow(data); data$reject2 = 1:nrow(data)
  predictors = c(predictors, "reject", "reject2")
  
  #### get variable types
  numb = names(which(unlist(lapply(data[,predictors], is.numeric))))
  cat = names(which(!(unlist(lapply(data[,predictors], is.numeric)))))
  make_cat = names(which(unlist(lapply(data[,predictors], function(x) length(unique(x))<21))))
    #### make_cat was there to tell the computer to generate prediction for UNIQUE variables, rather than a range
    #### but it also converts it to categorical variables, which makes predict fail. The fix falls right before "return"
  # remove a numb variable if it was found through make_cat
  if (length(numb)>2 & sum(numb[1:(length(numb)-2)] %in% make_cat)>0) {
    byby = which(numb[1:(length(numb)-2)] %in% make_cat)
    number_me_back = numb[byby]
    numb = numb[-byby] 
  }
  make_cat = unique(c(cat, make_cat))
  
  ##### make "quadriture" points for quant variables
  var.mins = apply(data[, numb], 2, min, na.rm=T)
  var.max = apply(data[, numb], 2, max, na.rm=T)  
  
  ### make quadriture points smaller if they're doing RF
  
  if (mod_class == "RandomForest" & num_points == 50){
    min.max = data.frame(var.mins, var.max); min.max$size = c(10, rep(8, nrow(min.max)-1))
  } else {
    min.max = data.frame(var.mins, var.max); min.max$size = c(num_points, rep(max(3,round(num_points/4)), nrow(min.max)-1))
  }  
  f = function(d){seq(from=d[1], to=d[2], length.out=d[3])}
  min.max = as.list(apply(min.max, 1, f))
  
  #### get unique values for categorical vars
  if (length(make_cat)==1){
    un.vars = lapply(data[make_cat], unique)    	
  } else {
    ## if the number of unique values is < 50, just use the unique values
    un.vars =lapply(data[,make_cat], unique); names(un.vars) = make_cat
  }
  
  
  #### combine into one dataset
  all.vars = c(min.max, un.vars)    
  #### get rid of extra variables
  tot.vars = length(predictors)
  rejects = grep("reject", names(all.vars))
  all.vars = all.vars[-rejects]
  all.vars = lapply(all.vars, function(x) x[!is.na(x)])
  pred.values = expand.grid(all.vars)

  #### if it's not in model 1:
  #### input the mean (if numeric) or a value (if categorical)
  # but first check whether its a RE model
  if (length(which(!(model_terms %in% predictors)))>0 ){
    not.in.there = model_terms[which(!(model_terms %in% predictors))]
    for (i in 1:length(not.in.there)){
      if (is.numeric(data[,not.in.there[i]])){
        message(paste0("Note: You didn't choose to plot ", not.in.there[i], " so I am inputting the median\n"))
        pred.values[,not.in.there[i]] = median(data[,not.in.there[i]], na.rm=T)
      } else {
        # this had issues when a random effect (as factor) was
        val = unique(as.character(data[[not.in.there[i]]]))[1]
        #only display the message if it's not a glmer mod
        if (!(mod_class %in% c("lmerMod", "glmerMod"))) {
          message(paste0("Note: You didn't choose to plot ", 
                       not.in.there[i], " so I am inputting '", val, "'\n"))
        }  
        pred.values[,not.in.there[i]] = val
      }
    }
  }

  if (exists("number_me_back")) {
    for (i in 1:length(number_me_back)) {
      pred.values[,number_me_back[i]] = as.numeric(as.character(pred.values[,number_me_back[i]]))
      attr(pred.values[,number_me_back[i]], "out.attrs") <- NULL
    }
  }

  return(pred.values)
}


generate_predictions = function(model, re, pred.values, pred.type, report.se) {

  model.type = class(model)[1]
  if ((model.type == "lmerMod" | model.type == "glmerMod") & !re){
    return(data.frame(prediction = 
                 predict(model, pred.values, type="response"), model="fixed effects"))
  }  
  
  if ((model.type == "lmerMod" | model.type == "glmerMod") & re){
    return(data.frame(
      prediction = 
                  predict(model, pred.values, type="response", re.form=NA), model="random effects"))
  }  
    
  if (model.type == "polr"){
      return(
        data.frame(prediction = predict(model, pred.values, type="class", re.form=NA), model= model.type)		
      )
  }

  if (model.type=="RandomForest") {
    
    ## get dataset to test that classes are all the same
    response = attr(model, "data")@get("response")
    outcome = attr(model, "data")@get("input")
    data = cbind(response, outcome)
    # check if classes differ from old to new, and correct if they are
    class_preds = lapply(pred.values, class)
    class_data = lapply(data[names(pred.values)], class)
    if (!identical(class_preds, class_data)) {
      for (i in 1:length(class_preds)) {
        if (class(data[,names(pred.values[i])])== "factor") 
          pred.values[,i] = factor(pred.values[,i], levels=levels(data[,names(pred.values[i])]))
        else 
          class(pred.values[,i]) = class(data[,names(pred.values[i])])
      }
    }
    
    prediction = predict(model, newdata=pred.values, OOB = TRUE)
    d = data.frame(prediction = prediction, model=model.type)
    names(d)[1] = "prediction"
    return(d
    )    
  }
  
  if (model.type == "rpart") {
    return(
      data.frame(prediction = predict(model, pred.values), model= model.type)		
    )
  }
  
  int = ifelse(report.se, "confidence", "none")
  return(
    data.frame(prediction = predict(model, pred.values, interval=int, type=pred.type), model=model.type)
  )
}


