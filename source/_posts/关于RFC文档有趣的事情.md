---
title:      关于RFC文档有趣的事情
categories:
    - 研究
tags:
    - RFC
    - 编号
    - python
---

原文为知乎[文章](https://zhuanlan.zhihu.com/p/337997798)， 现转移到个人博客。

# Table of Contents

1.  [事情的起源](#org34ce3f0)
2.  [研究经过](#orgbd0ef9b)
    1.  [查询相关资料](#orgd742468)
    2.  [查询相关RFC](#org7b36c8c)
    3.  [一个想法](#orge2e0fc8)
        1.  [第一个发现](#org3061772)
        2.  [第二个发现](#org4e04c37)
        3.  [第三个发现](#org2636b5a)
        4.  [第四个发现](#org9ff55be)
3.  [总结](#org9564d4b)



<a id="org34ce3f0"></a>

# 事情的起源

一次被问起，为何TLSv1.0(RFC2246),TLSv1.1(RFC4346),TLSv1.2(RFC5246),TLSv1.3(RFC8446)中的RFC编号都是以64结尾。印象中关于RFC编号都是递增的，因为RFC写好之后就不允许再修改了，如果有新的标准出来，只能在其后某个编号出现，并且引用之前的RFC。
但是上述这个问题，TLS四个版本均以64结尾，也太凑巧了，确实很让人疑惑。本着好奇，去研究了研究这事。

<！--more-->

<a id="orgbd0ef9b"></a>

# 研究经过


<a id="orgd742468"></a>

## 查询相关资料

首先在网上搜索为什么TLS均以64结尾，网上的回答基本上来自如下解释

> In the IETF, protocols are called RFCs. TLS 1.0 was RFC 2246, TLS 1.1 was RFC 4346, and TLS 1.2 was RFC 5246. Today, TLS 1.3 was published as RFC 8446. RFCs are generally published in order, keeping 46 as part of the RFC number is a nice touch<sup><a id="fnr.1" class="footref" href="#fn.1">1</a></sup>.

显然，并没有解决我们的问题。


<a id="org7b36c8c"></a>

## 查询相关RFC

思考是否会有某个RFC对这事做了说明吗？查询未果。
但是在此过程中，我发现了在RFC文档中，有相邻两个递增编号文档，但是RFC时间并不递增的现象。举个例子

> 1478 An Architecture for Inter-Domain Policy Routing. M. Steenstrup. June
> 
> 1.  (Format: TXT, HTML) (Status: HISTORIC) (DOI: 10.17487/RFC1478)
> 
> 1479 Inter-Domain Policy Routing Protocol Specification: Version 1. M.
>      Steenstrup. July 1993. (Format: TXT, HTML) (Status: HISTORIC) (DOI:
>      10.17487/RFC1479) 
> 
> 1480 The US Domain. A. Cooper, J. Postel. June 1993. (Format: TXT, HTML)
>      (Obsoletes RFC1386) (Status: INFORMATIONAL) (DOI: 10.17487/RFC1480) 

其中RFC1478的时间为1993年6月，RFC1479的时间为1993年7月，但是RFC1480的时间为1993年6月，出现了非递增的情况。

虽然又发现，但好像并没有什么卵用。但是自然会想到，有可能时间上有大的反复吗？有年的反复现象吗？


<a id="orge2e0fc8"></a>

## 一个想法


<a id="org3061772"></a>

### 第一个发现

所以就想分析分析RFC文档的编号的时间问题。第一想法是爬虫，但是工作量太复杂。左搜索右搜索，找到了官网提供的XML版列表<sup><a id="fnr.2" class="footref" href="#fn.2">2</a></sup>.超级开心。然后写了个python脚本，自动进行了分析(忽略并不想改的变量名，来自一个豆瓣电影爬虫)。
```python
    #!/usr/bin/python3
    import calendar
    from xml.dom.minidom import parse
    import xml.dom.minidom
    
    import numpy as np
    import matplotlib.pyplot as plt 
    
    # 使用minidom解析器打开 XML 文档
    DOMTree = xml.dom.minidom.parse("rfc-index.xml")
    collection = DOMTree.documentElement
    if collection.hasAttribute("shelf"):
       print ("Root element : %s" % collection.getAttribute("shelf"))
    
    # 在集合中获取所有电影
    movies = collection.getElementsByTagName("rfc-entry")
    
    # 打印每部电影的详细信息
    print ("*****Movie*****")
    x = [];
    years = [];
    months = [];
    total = [];
    for movie in movies:
    
       type = movie.getElementsByTagName('doc-id')[0].childNodes[0].data
    
       id = int(type[3:]);
       x.append(id);
    #    print ("doc-id: %d" % id)
    #    author = movie.getElementsByTagName('author')[0]
    #    print ("author: %s" % author.childNodes[1].data)
       date = movie.getElementsByTagName('date')[0]
       month = date.getElementsByTagName('month')[0].childNodes[0].data;
       int_month = int(list(calendar.month_name).index(month))
       months.append(int_month);
    #    print ("date month: %d" % int_month)
       year = int(date.getElementsByTagName('year')[0].childNodes[0].data);
    #    print ("date year: %d" % year)
       years.append(year);
    #    description = movie.getElementsByTagName('description')[0]
    #    print ("Description: %s" % description.childNodes[0].data)
       total.append(year + 10  + int_month  )
    
    plt.rcParams['font.sans-serif'] = ['Arial Unicode MS']
    plt.rcParams['axes.unicode_minus'] = False   # 解决保存图像是负号'-'显示为方块的问题
    plt.title("Matplotlib") 
    plt.xlabel("RFC编号") 
    plt.ylabel("年份") 
    
    plt.plot(x,years, label=r'年') 
    plt.plot(x,total, label=r'年 + 月 + 10(向上平移10)') 
    # plt.subplot(2,1,1)
    # plt.plot(x,years) 
    # plt.subplot(2,1,2)
    # plt.plot(x,months) 
    plt.legend();
    
    plt.grid()
    plt.show()
```
经过经过分析有了如下所示图：
![img](年份图.png)
果然有问题！！！！上图横坐标为RFC编号，纵坐标为RFC编号对应的年份。可以看出RFC文档从一九六几年到今天一共发表8000余份。有意思的是，其中有一些凸起的部分，就是一些异常点。例如2000年前有一个极高的凸起，这代表这个编号的年份远远超出这个编号附近的年份，这与我们的常识不符。实际上，查看这个异常点，如下图所示：
![img](image-20201218225458777.png)
其中RFC1849的年份为2010年，但其附近的RFC文档编号均为1995年，其中相差15年，造成第一幅图中的凸起。


<a id="org4e04c37"></a>

### 第二个发现

同时，我们还会发现另一个有意思的现象。如下图所示：
![整数间隔示意图](整数间隔示意图.png)
其中编号为1299，1399，1499，1599，1699,&#x2026;等，均出现凸起现象。并且实际上1299，1399，1499，1599，1699，1799，1899，1999的年份均为1997年。存在明显的人为痕迹。


<a id="org2636b5a"></a>

### 第三个发现

年份和月份基本满足递增，但是有波动。如下图所示：
![img](示意图.png)
放大后：
![img](示意图放大.png)
为方便对比，将其中月份显示为（年+月，再向上平移10个单位(年)）。


<a id="org9ff55be"></a>

### 第四个发现

TLS的主要作者，目前是Eric Rescorla。对TLS四个版本作者做简单统计，如下图：
![img](image-20201218231640006.png)
可以看出，最开始Tim Dierks逐渐从第二作者，向第一作者上升，此时带了个徒弟。慢慢Tim Dierks开始退居二线，Eric Rescorla开始独挡一面（纯属胡说八道）。


<a id="org9564d4b"></a>

# 总结

虽然并没有直接的证据来回答开头提出的问题，但是我们可以发现以下现象：

-   RFC的编号并非严格的时间递增，而是存在一些波动
-   RFC的编号中存在一些，小概率发生的现象，例如等间隔凸起

基于以上现象呢，我们可以大胆猜测（hu shuo ba dao）：

-   RFC编号的审批机构，会因为某些原因，保留一些编号
-   RFC的编号其实并没有想象中的那么严格
-   大佬在RFC编号中具有一定的发言权，可以”预定“一些编号。如TLSv1，2，3，4以64结尾


# Footnotes

<sup><a id="fn.1" href="#fnr.1">1</a></sup> <https://blog.cloudflare.com/rfc-8446-aka-tls-1-3/>

<sup><a id="fn.2" href="#fnr.2">2</a></sup> <https://www.rfc-editor.org/rfc-index.xml>
