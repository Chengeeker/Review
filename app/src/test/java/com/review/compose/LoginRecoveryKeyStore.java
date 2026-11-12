package com.review.compose;
import java.security.*;
import java.security.cert.Certificate;
import java.io.*;
import java.util.*;
public final class LoginRecoveryKeyStore extends KeyStoreSpi {
    public static Key key;
    public Key engineGetKey(String alias,char[] password){return key;}
    public Certificate[] engineGetCertificateChain(String alias){return null;}
    public Certificate engineGetCertificate(String alias){return null;}
    public Date engineGetCreationDate(String alias){return null;}
    public void engineSetKeyEntry(String alias,Key key,char[] password,Certificate[] chain){throw new UnsupportedOperationException();}
    public void engineSetKeyEntry(String alias,byte[] key,Certificate[] chain){throw new UnsupportedOperationException();}
    public void engineSetCertificateEntry(String alias,Certificate cert){throw new UnsupportedOperationException();}
    public void engineDeleteEntry(String alias){throw new UnsupportedOperationException();}
    public Enumeration<String> engineAliases(){return Collections.emptyEnumeration();}
    public boolean engineContainsAlias(String alias){return key!=null;}
    public int engineSize(){return key==null?0:1;}
    public boolean engineIsKeyEntry(String alias){return key!=null;}
    public boolean engineIsCertificateEntry(String alias){return false;}
    public String engineGetCertificateAlias(Certificate cert){return null;}
    public void engineStore(OutputStream stream,char[] password){}
    public void engineLoad(InputStream stream,char[] password){}
}
