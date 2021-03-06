
#' convert phrases into single tokens
#' 
#' Replace multi-word phrases in text(s) with a compound version of the phrases 
#' concatenated with  \code{concatenator} (by default, the "\code{_}" character) to
#' form a single token.  This prevents tokenization of the phrases during 
#' subsequent processing by eliminating the whitespace delimiter.
#' @param object source texts, a character or character vector
#' @param phrases a \code{\link{dictionary}} object that 
#'   contains some phrases, defined as multiple words delimited by whitespace, 
#'   up to 9 words long; or a quanteda collocation object created
#'   by \code{\link{collocations}}
#' @param concatenator the concatenation character that will connect the words 
#'   making up the multi-word phrases.  The default \code{_} is highly 
#'   recommended since it will not be removed during normal cleaning and 
#'   tokenization (while nearly all other punctuation characters, at least those
#'   in the Unicode punctuation class [P] will be removed.
#' @return character or character vector of texts with phrases replaced by 
#'   compound "words" joined by the concatenator
#' @export
#' @author Kenneth Benoit
#' @keywords internal deprecated
#' @examples
#' mytexts <- c("The new law included a capital gains tax, and an inheritance tax.",
#'              "New York City has raised a taxes: an income tax and a sales tax.")
#' mydict <- dictionary(list(tax=c("tax", "income tax", "capital gains tax", "inheritance tax")))
#' (cw <- phrasetotoken(mytexts, mydict))
#' dfm(cw, verbose=FALSE)
#' 
#' # when used as a dictionary for dfm creation
#' mydfm2 <- dfm(cw, dictionary = lapply(mydict, function(x) gsub(" ", "_", x)))
#' mydfm2
#' # to pick up "taxes" in the second text, set valuetype = "regex"
#' mydfm3 <- dfm(cw, dictionary = lapply(mydict, phrasetotoken, mydict),
#'               valuetype = "regex")
#' mydfm3
#' ## one more token counted for "tax" than before
setGeneric("phrasetotoken", 
           function(object, phrases, ...) 
               standardGeneric("phrasetotoken"))

#' @rdname phrasetotoken
#' @export
setMethod("phrasetotoken", signature = c("corpus", "ANY"), 
          function(object, phrases, ...) {
              texts(object) <- phrasetotoken(texts(object), phrases, ...)
              object
          })

setOldClass("tokenizedTexts")
setClassUnion("textORtokens", members =  c("character", "tokenizedTexts"))

#' @rdname phrasetotoken
#' @export
#' @examples 
#' # using a dictionary to pre-process multi-word expressions
#' myDict <- dictionary(list(negative = c("bad* word*", "negative", "awful text"),
#'                           postiive = c("good stuff", "like? th??")))
#' txt <- c("I liked this, when we can use bad words, in awful text.",
#'          "Some damn good stuff, like the text, she likes that too.")
#' phrasetotoken(txt, myDict)
#'
setMethod("phrasetotoken", signature = c("textORtokens", "dictionary"), 
          function(object, phrases, ...) {
              phraseConcatenator <- phrases@concatenator
              phrasesTmp <- unlist(phrases, use.names = FALSE)
              compoundPhrases <- phrasesTmp[stringi::stri_detect_fixed(phrasesTmp, phraseConcatenator)]
              # replace string concatenator with simple space
              compoundPhrases <- stringi::stri_replace_all_fixed(compoundPhrases, phraseConcatenator, " ")
              phrasetotoken(object, compoundPhrases, ...)
          })


setClass("collocations", contains = "data.table")

#' @rdname phrasetotoken
#' @export
setMethod("phrasetotoken", signature = c("textORtokens", "collocations"), 
          function(object, phrases, ...) {
              word1 <- word2 <- word3 <- NULL
              # sort by word3 so that trigrams will be processed before bigrams
              data.table::setorder(phrases, -word3, word1)
              # concatenate the words                               
              word123 <- phrases[, list(word1, word2, word3)]
              mwes <- apply(word123, 1, paste, collapse=" ")
              # strip trailing white space (if no word 3)
              mwes <- stringi::stri_trim_both(mwes)
              phrasetotoken(object, mwes, ...)
          })

#' @rdname phrasetotoken
#' @inheritParams valuetype
#' @param case_insensitive if \code{TRUE}, ignore case when matching
#' @param ... additional arguments passed through to core \code{"character,character"} method
#' @export
#' @examples 
#' # on simple text
#' \donttest{
#' phrasetotoken("This is a simpler version of multi word expressions.", "multi word expression*")
#' }
setMethod("phrasetotoken", signature = c("character", "character"), 
          function(object, phrases, concatenator = "_", valuetype = c("glob", "regex", "fixed"), 
                   case_insensitive = TRUE, ...) {
              valuetype <- match.arg(valuetype)
              if (valuetype == "glob" | valuetype == "fixed") {
                  compoundPhrases <- stringi::stri_replace_all_fixed(phrases, c("*", "?"), 
                                                                     c("[^\\s]*", "[^\\s]"), 
                                                                     vectorize_all = FALSE)
                  # replace any + symbols that are tokens by escaped \\+ #239
                  compoundPhrases <- stringi::stri_replace_all_regex(phrases, "(\\s{0,1})\\+(\\s{0,1})", "$1\\\\\\+$2")
              }
              
              compoundPhrasesList <- strsplit(compoundPhrases, "\\s")
              
              for (l in compoundPhrasesList) {
                  re.search <- paste("(\\b", paste(l, collapse = paste0(")\\p{WHITE_SPACE}+(")), "\\b)", sep = "")
                  re.replace <- paste("$", 1:length(l), sep = "", collapse = concatenator)
                  object <- stringi::stri_replace_all_regex(object, re.search, re.replace, case_insensitive = case_insensitive)
              }
              object
          })


#' @rdname phrasetotoken
#' @export
#' @examples 
#' \donttest{
#' # on simple text
#' toks <- tokenize("Simon sez the multi word expression plural is multi word expressions, Simon sez.")
#' phrases <- c("multi word expression*", "Simon sez")
#' phrasetotoken(toks, phrases)
#' }
setMethod("phrasetotoken", signature = c("tokenizedTexts", "character"), 
          function(object, phrases, concatenator = "_", valuetype = c("glob", "regex", "fixed"), 
                   case_insensitive = TRUE, ...) {
              valuetype <- match.arg(valuetype)
              
              # convert any patterns to fixed matches
              phrasesTok <- tokenize(phrases, what = "fasterword")
              attr.orig <- attributes(phrasesTok)
              class.orig <- class(phrasesTok)
              
              if (valuetype %in% c("glob", "fixed"))
                  phrasesTok <- lapply(phrasesTok, glob2rx)
              phrasesTokFixed <- regexToFixed(object, phrasesTok, case_insensitive = case_insensitive)
              attributes(phrasesTokFixed) <- attr.orig
              class(phrasesTokFixed) <- class.orig
              
              # joinTokens(object, phrasesTokFixed, valuetype = "fixed", case_insensitive = FALSE)
              tokens_compound(object, phrasesTokFixed, valuetype = "fixed", case_insensitive = FALSE)
})

regexToFixed <- function(tokens, patterns, case_insensitive = FALSE, types = NULL) {
    
    # get unique token types
    if (is.null(types)) types <- unique(unlist(tokens))
    
    seqs_token <- list()
    for (seq_regex in patterns) {
        match <- lapply(seq_regex, function(x, y) y[stringi::stri_detect_regex(y, x, case_insensitive = case_insensitive)], types)
        if (length(unlist(seq_regex)) != length(match)) next
        match_comb <- as.matrix(do.call(expand.grid, c(match, stringsAsFactors = FALSE))) # produce all possible combinations
        seqs_token <- c(seqs_token, unname(split(match_comb, row(match_comb))))
    }
    seqs_token
}



