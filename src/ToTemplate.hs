module ToTemplate where

import qualified Text.Parsec as Parsec
import Text.Parsec ((<|>))

import Obj
import Types
import Parsing
import Util

-- | High-level helper function for creating templates from strings of C code.
toTemplate :: String -> [Token]
toTemplate text = case Parsec.runParser templateSyntax 0 "(template)" text of
                    Right ok -> ok
                    Left err -> error (show err)
  where
    templateSyntax :: Parsec.Parsec String Int [Token]
    templateSyntax = Parsec.many parseTok

    parseTok = Parsec.try parseTokDecl <|>      --- $DECL
               Parsec.try parseTokName <|>      --- $NAME
               Parsec.try parseTokTyGrouped <|> --- i.e. $(Fn [Int] t)
               Parsec.try parseTokTyRawGrouped <|>
               Parsec.try parseTokTy <|>        --- i.e. $t
               parseTokC                        --- Anything else...

    parseTokDecl :: Parsec.Parsec String Int Token
    parseTokDecl = do _ <- Parsec.string "$DECL"
                      return TokDecl

    parseTokName :: Parsec.Parsec String Int Token
    parseTokName = do _ <- Parsec.string "$NAME"
                      return TokName

    parseTokC :: Parsec.Parsec String Int Token
    parseTokC = do s <- Parsec.many1 validInSymbol
                   return (TokC s)
      where validInSymbol = Parsec.choice [Parsec.letter, Parsec.digit, Parsec.oneOf validCharactersInTemplate]
            validCharactersInTemplate = " ><{}()[]|;:.,_-+*#/'^!?€%&=@\"\n\t"

    parseTokTy :: Parsec.Parsec String Int Token
    parseTokTy = do _ <- Parsec.char '$'
                    s <- Parsec.many1 Parsec.letter
                    return (toTokTy Normal s)

    parseTokTyGrouped :: Parsec.Parsec String Int Token
    parseTokTyGrouped = do _ <- Parsec.char '$'
                           _ <- Parsec.char '('
                           Parsec.putState 1 -- One paren to close.
                           s <- fmap ('(' :) (Parsec.many parseCharBalanced)
                           -- Note: The closing paren is read by parseCharBalanced.
                           return (toTokTy Normal s)

    parseTokTyRawGrouped :: Parsec.Parsec String Int Token
    parseTokTyRawGrouped = do _ <- Parsec.char '§'
                              _ <- Parsec.char '('
                              Parsec.putState 1 -- One paren to close.
                              s <- fmap ('(' :) (Parsec.many parseCharBalanced)
                              -- Note: The closing paren is read by parseCharBalanced.
                              return (toTokTy Raw s)

    parseCharBalanced :: Parsec.Parsec String Int Char
    parseCharBalanced = do balanceState <- Parsec.getState
                           if balanceState > 0
                             then Parsec.try openParen <|>
                                  Parsec.try closeParen <|>
                                  Parsec.anyChar
                             else Parsec.char '\0' -- Should always fail which will end the string.

    openParen :: Parsec.Parsec String Int Char
    openParen = do _ <- Parsec.char '('
                   Parsec.modifyState (+1)
                   return '('

    closeParen :: Parsec.Parsec String Int Char
    closeParen = do _ <- Parsec.char ')'
                    Parsec.modifyState (\x -> x - 1)
                    return ')'

-- | Converts a string containing a type to a template token ('TokTy').
-- | i.e. the string "(Array Int)" becomes (TokTy (StructTy "Array" IntTy)).
toTokTy :: TokTyMode -> String -> Token
toTokTy mode s =
  case parse s "" of
    Left err -> error (show err)
    Right [] -> error ("toTokTy got [] when parsing: '" ++ s ++ "'")
    Right [xobj] -> case xobjToTy xobj of
                      Just ok -> TokTy ok mode
                      Nothing -> error ("toTokTy failed to convert this s-expression to a type: " ++ pretty xobj)
    Right xobjs -> error ("toTokTy parsed too many s-expressions: " ++ joinWithSpace (map pretty xobjs))
