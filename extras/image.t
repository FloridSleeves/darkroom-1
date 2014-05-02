local cstdio = terralib.includec("stdio.h")
local cstdlib = terralib.includec("stdlib.h")
local cstring = terralib.includec("string.h")

pageSize = 4*1024

local chack = terralib.includecstring [[
#include<stdio.h>
#include <string.h>
#include <stdlib.h>
#include <assert.h>

int seek_set(void){ return SEEK_SET; }
int seek_cur(void){ return SEEK_CUR; }
int seek_end(void){ return SEEK_END; }

unsigned char* loadPPM_UC(const char *filename, int* width, int* height, int* channels, int* outBits){

  printf("Load ppm %s\n",filename);
  FILE *file = fopen(filename,"rb");

  if ( file==NULL){
      printf("Failed to open file: %s\n" , filename ) ;
      return 0 ;
  }

  char key[16];
  char junk[16];
  int  maxC ; 
  int cnt = 0 ; 
  cnt += fscanf( file , "%s" , key ); //Read the P6
  cnt += fscanf( file , "%d" , width ); //Read the ascii formatted width
  cnt += fscanf( file , "%d" , height ); //Read the ascii formatted height
  cnt += fscanf( file , "%d" , &maxC ); //Read the ascii formatted max color channel
  cnt += fscanf( file , "%c" , junk ); // Read the single white space character
  
  if(strcmp(key,"P6")!=0 && strcmp(key,"P5")!=0){
    printf("Error, incorrect PPM type %s\n",key);
    return 0;
  }

  if( cnt != 5 ){
    printf("Error, failed to read 5 char items in file: %s\n" , filename ) ;
    return 0 ;
  }
 
  printf( "INFO: PPM load %s %s %d %d %d\n" , filename , key , *width , *height , maxC ) ;

  if(strcmp(key,"P6")==0){
    *channels = 3; // always 3 for this type
  }else if(strcmp(key,"P5")==0){
    *channels = 1; 
  }

    int bytes = 1;

  if( maxC <=  255 ){
//    printf("error, this function doesn't support 16 bit\n");
//    return 0;
    printf("8 bit\n");
    *outBits = 8;
  }else  if( maxC < 65535 ){
    printf("16 bit\n");
    bytes = 2;
    *outBits = 16;
  }else{
    printf("unsupported bit depth %d\n",maxC);
    return 0;
  }
  
  // read in data
  unsigned char *data = malloc( (*width) * (*height) * (*channels) * bytes);
  unsigned char *tempData = malloc( (*width) * (*height) * (*channels) * bytes);

  int i = 0;
  if ((i = fread(tempData, (*width)*(*height)*(*channels)*sizeof(unsigned char) * bytes, 1, file)) != 1) {
    printf("Error reading file\n");
    return 0;
  }

  // flip row order
  int typewidth = (*channels)*bytes;
  for(int c=0; c<typewidth; c++){
    for(int x=0; x<(*width); x++){ 
      for(int y=0; y<(*height); y++){
        data[(((*height)-y-1)*(*width)+x)*typewidth+c] = tempData[(y*(*width)+x)*typewidth+c];
      }
    }
  }

  //delete[] tempData;
  free(tempData);

  return data;
}

int saveBMP_UC(const char *filename, int width, int height, int stride, int channels, unsigned char *data){

  FILE *file;
    
  // make sure the file is there.
  if ((file = fopen(filename, "wb"))==NULL){
    printf("could't open file for writing %s",filename);
    return 0;
  }
    
  unsigned char BMPheader[2]={66,77};

  if ((fwrite(&BMPheader, sizeof(BMPheader), 1, file)) != 1) {
    printf("[Bmp::save] Error writing header");
    return 0;
  }
    
  unsigned int totalsize=width * height * 3 +54; // we always write 3 channels
    
  if ((fwrite(&totalsize, sizeof(totalsize), 1, file)) != 1) {
    printf("[Bmp::save] Error writing header");
    return 0;
  }

  totalsize=0;
    
  if ((fwrite(&totalsize, sizeof(totalsize), 1, file)) != 1) {
    printf("[Bmp::save] Error writing header");
      
    return 0;
      
  }
    
  //offset to data=54
  totalsize=54;
    
  if ((fwrite(&totalsize, sizeof(totalsize), 1, file)) != 1) {
    printf("[Bmp::save] Error writing header");
      
    return 0;
      
  }
    
  //	Size of InfoHeader =40 
  totalsize=40;
    
  if ((fwrite(&totalsize, sizeof(totalsize), 1, file)) != 1) {
    printf("[Bmp::save] Error writeing header");
      
    return 0;
      
  }
    
  unsigned int owidth=width;
  unsigned int oheight=height;
    
  // write the width
  if ((fwrite(&owidth, 4, 1, file)) != 1) {
    printf("Error writeing width");
      
    return 0;
      
  }
    
  // write the height 
  if ((fwrite(&oheight, 4, 1, file)) != 1) {
    printf("Error writing height");
      
    return 0;
  }
    
    
  // write the planes
  unsigned short int planes=1;
    
  if ((fwrite(&planes, 2, 1, file)) != 1) {
    printf("Error writeing planes");
      
    return 0;
  }
    
  // write the bpp
  unsigned short bitsPP = 24;
    
  if ((fwrite(&bitsPP, 2, 1, file)) != 1) {
    printf("[Bmp save] Error writeing bpp");
    return 0;
  }
    
  //compression
  unsigned int comp=0;
    
  if ((fwrite(&comp, 4, 1, file)) != 1) {
    printf("Error writeing planes to ");
    return 0;
  }
    
  //imagesize
  comp=0;
    
  if ((fwrite(&comp, 4, 1, file)) != 1) {
    printf("Error writeing planes to ");
    return 0;
  }
    
  //XpixelsPerM
  comp=0;
    
  if ((fwrite(&comp, 4, 1, file)) != 1) {
    printf("Error writeing planes to ");
    return 0;
  }
    
  //YpixelsPerM
  comp=0;
    
  if ((fwrite(&comp, 4, 1, file)) != 1) {
    printf("Error writeing planes to ");
    return 0;
  }
    
  //ColorsUsed
  comp=0;
    
  if ((fwrite(&comp, 4, 1, file)) != 1) {
    printf("Error writeing planes to ");
    return 0;
  }
    
  //ColorsImportant
  comp=0;
     
  if ((fwrite(&comp, 4, 1, file)) != 1) {
    printf("Error writeing planes to ");
    return 0;
  }
    
  // read the data. 
    
  if (data == NULL) {
    printf("[Bmp save] No image data to write!");
    return 0;	
  }
    
  unsigned char temp;

  // bmps pad each row to be a multiple of 4 bytes
  int padding = 4 - (width * 3 % 4); // we always write 3 channels
  padding = padding == 4 ? 0 : padding;
  char pad[]={0,0,0};

  if(channels==3){
    // calculate the size (assuming 24 bits or 3 bytes per pixel).
    unsigned long size = height * width * channels;

    unsigned char* tempData = malloc(sizeof(unsigned char)*width*height*3);

    for (unsigned int y=0; y<height; y++) { // reverse all of the colors. (bgr -> rgb)
      for (unsigned int x=0; x<width*3; x+=3){
        int i=y*width*3+x;
        int ii = y*stride*3+x;
        tempData[i] = data[ii+2];
        tempData[i+1] = data[ii+1];
        tempData[i+2] = data[ii];
      }
    }
    
    if(padding != 0){
      for(int h=0; h<height; h++){
        fwrite(&tempData[h*width*channels], width*channels, 1, file);
        fwrite(pad,padding,1,file);
      }
    }else{
      if ((fwrite(tempData, size, 1, file)) != 1) {
        printf("[Bmp save] Error writeing image data");
        return 0;
      }
    }

    free(tempData);
      
  }else if(channels==1){
    //we need to expand an alpha into 3 components so taht it can actually be read
    //unsigned char* expanded=new unsigned char[width*height*3];
    unsigned char* expanded=malloc(sizeof(unsigned char)*width*height*3);
      
    for(int y=0; y<height; y++){
      for(int x=0; x<width; x++){
        int i = (y*width+x)*3;
        int ii = y*stride+x;
        expanded[i]=data[ii];
        expanded[i+1]=data[ii];
        expanded[i+2]=data[ii];
      }
    }
       
    if(padding != 0){
      for(int h=0; h<height; h++){
        fwrite(&expanded[h*width*3], width*3, 1, file);
        fwrite(pad,padding,1,file);
      }
    }else{
      if ((fwrite(expanded,width*height*3, 1, file)) != 1) {
        printf("[Bmp save] Error writing image data");
        //delete[] expanded;
        free(expanded);
        return 0;
      }
    }

    //delete[] expanded;
    free(expanded);
  }else{
    printf("Error, image has %d channels!\n",channels);
    assert(0); 
  }
    
    
  fclose(file);

  // were done.
  return 1;
}

int saveImageUC(
  const char *filename, 
  int width, 
  int height, 
  int stride,
  int channels, 
  unsigned char *data){

  const char *ext = filename + strlen(filename) - 3;

  if(strcmp(ext,"bmp")==0){
    return saveBMP_UC(filename,width,height,stride,channels,data);
  }

  printf("Couldn't save UC, bad ext %s\n", ext);
  return 0;
}

int saveBMPAutoLevels(const char *filename, int width, int height, int stride, int channels, float *data){
  // convert float to unsigned char
  assert(stride>=width);

  unsigned char *temp = malloc(sizeof(unsigned char)*stride*height*channels);

  float max = -1000000.f;
  float min = 1000000.f;

  float *idata = data;

  for( int y=0; y<height; y++ ){
    for( int x=0; x<width*channels; x++){
      if(*idata<min){min=*idata;}
      if(*idata>max){max=*idata;}
      idata++;
    }
    idata = idata + (stride-width)*channels;
  }

  printf("w %d stride %d c %d\n",width,stride,channels);

  printf("Auto Levels Max: %f\n", max);
  printf("Auto Levels Min: %f\n", min);

  idata = data;
  unsigned char *itemp = temp;
  for( int y=0; y<height; y++ ){
    for( int x=0; x<width*channels; x++ ){
      *itemp = (unsigned char)( ((*idata-min)/(max-min)) * 255.f );
      idata++;
      itemp++;
    }
    idata = idata + (stride-width)*channels;
    itemp = itemp + (stride-width)*channels;
  }


  int res = saveBMP_UC(filename,width,height,stride,channels,temp);
  free(temp);

  return res;
}

int saveImageAutoLevels(const char *filename, int width, int height, int stride, int channels, float *data){
  const char *ext = filename + strlen(filename) - 3;

  if(strcmp(ext,"bmp")==0){
    return saveBMPAutoLevels( filename, width, height, stride, channels, data );
  }

  printf("Couldn't save Auto Levels, bad ext %s\n", ext);
  return 0;
}

#define TAG_FLOAT 202021.25  // check for this when READING the file
#define TAG_STRING "PIEH"    // use this when WRITING the file

int saveFLO(const char *filename, int width, int height, int stride, float *data){
  FILE *stream = fopen(filename, "wb");
  assert(stream);//, "Could not open %s", filename.c_str());
        
  // write the header
  fprintf(stream, TAG_STRING);
  if( (int)fwrite(&width,  sizeof(int), 1, stream) != 1 ){
    assert(0);
  }
  
  if( (int)fwrite(&height, sizeof(int), 1, stream) != 1 ){
    assert(0);//panic("problem writing header: %s", filename.c_str());
  }

  //float *dataTemp = new float[width*height*2];
  float *dataTemp = malloc(sizeof(float)*width*height*2);

  // flip row order
  for(int x=0; x<width;x++){
    for(int y=0; y<height; y++){
      dataTemp[((height-y-1)*width+x)*2+0] = data[(y*stride+x)*2+0];
      dataTemp[((height-y-1)*width+x)*2+1] = data[(y*stride+x)*2+1];
    }
  }

  fwrite(dataTemp, sizeof(float), width * height * 2, stream);
  fclose(stream);

  //delete[] dataTemp;
  free(dataTemp);

  return 1;
}

int saveBMP_F(const char *filename, int width, int height, int stride, int channels, float *data){
  // convert float to unsigned char

  //unsigned char *temp = new unsigned char[width*height*channels];
  unsigned char *temp = malloc(sizeof(unsigned char)*width*height*channels);

  for(int i=0; i<width*height*channels; i++){
    temp[i] = (unsigned char)( ((data[i]+1.f)/2.f) * 255.f );
  }

  int res = saveBMP_UC( filename, width, height, stride, channels, temp );
  //delete[] temp;
  free(temp);

  return res;
}

int saveBMP_I(const char *filename, int width, int height, int stride, int channels, int *data){
  // convert Int to unsigned char

  //unsigned char *temp = new unsigned char[width*height*channels];
  unsigned char *temp = malloc(sizeof(unsigned char)*width*height*channels);

  for(int i=0; i<width*height*channels; i++){
    temp[i] = (unsigned char)( data[i] );
  }

  int res = saveBMP_UC( filename, width, height, stride, channels, temp );
  //delete[] temp;
  free(temp);

  return res;
}

int saveImageF(const char *filename, int width, int height, int stride, int channels, float *data){
  const char *ext = filename + strlen(filename) - 3;

  if(strcmp(ext,"bmp")==0){
    return saveBMP_F( filename, width, height, stride, channels, data );
  }else if(strcmp(ext,"flo")==0){
    assert(channels==2);
    return saveFLO(filename,width,height,stride,data);
  }

  return 0;
}

int saveImageI(const char *filename, int width, int height, int stride, int channels, int *data){
  const char *ext = filename + strlen(filename) - 3;

  if(strcmp(ext,"bmp")==0){
    return saveBMP_I( filename, width, height, stride, channels, data );
  }else if(strcmp(ext,"flo")==0){
    assert(0);
  }

  printf("Error unknown filetype %s\n",ext);
  return 0;
}

void writeRawImgToFile(const char* fname,
                       int width,
                       int height,
                       int stride,
                       int pixBitDepth,
                       int* img)
{
  printf("Writing raw W:%d H:%d bits:%d\n",width,height,pixBitDepth);

  unsigned char* data;
  unsigned int mask = (1 << pixBitDepth) - 1;
  int CHAR_BIT = 8;
  int bytesPerPix = (((pixBitDepth % CHAR_BIT) == 0) ? (pixBitDepth/CHAR_BIT) : (pixBitDepth/CHAR_BIT+1));
  int fctr;
  if (bytesPerPix <= 1)
  {
    fctr = 1;
    data = malloc(fctr*width*height);//new unsigned char[fctr*width*height];
    //for (k = 0; k < height*width; k++)
    //{
      for(int y=0; y<height; y++){
        for(int x =0; x<width; x++){
      data[y*width+x] = (unsigned char) ((img[y*stride+x] & mask) & 0xFF);
                                   }
                                 }

    //}
  } 
  else if (bytesPerPix <= 2)
    {
      fctr = 2;
      data = malloc(fctr*width*height);
//      for (k = 0; k < height*width; k++)
//      {
      for(int y=0; y<height; y++){
        for(int x =0; x<width; x++){
          data[2*(y*width+x)]= (unsigned char) ((img[y*stride+x] & mask) & 0xFF);
          data[2*(y*width+x)+1] = ((unsigned char) (((img[y*stride+x] & mask) >> 8) & 0xFF));
                                   }
      }
    }
    else if (bytesPerPix <= 4)
      {
        fctr = 4;

        data = malloc(fctr*width*height);
//        for (k = 0; k < height*width; k++)
//        {
      for(int y=0; y<height; y++){
        for(int x =0; x<width; x++){
          data[4*(y*width+x)]= (unsigned char) ((img[y*stride+x] & mask) & 0xFF);
          data[4*(y*width+x)+1]= (unsigned char) (((img[y*stride+x] & mask) >> 8) & 0xFF);
          data[4*(y*width+x)+2]= (unsigned char) (((img[y*stride+x] & mask) >> 16) & 0xFF);
          data[4*(y*width+x)+3] = (unsigned char) (((img[y*stride+x] & mask) >> 24) & 0xFF);
        }
                                 }
      }
      else 
        {
          printf("in readImg - a max of 4 bytes/pixel is supported - please check input image/parameters)");
          exit(-1);
        }
        
  FILE *file;
    
  // make sure the file is there.
  if ((file = fopen(fname, "wb"))==NULL){
    printf("could't open file for writing %s",fname);
    return;
  }

    //    ofstream ofs(fname.c_str(), ios::out | ios::binary);
        //assert(ofs.good());
  //      ofs.write((char *) data, fctr*height*width);
  fwrite(data,1,fctr*height*width,file);
   //     ofs.close();
   fclose(file);
  //      delete[] data;
  free(data);
  }

unsigned char* readRawImg(char* imgName,
                int width,
                int height,
                int pixBitDepth,
                int header,
                unsigned char flipEndian,
                int* bytesPerPix // how many bytes/pixel is the output?
                         )
{
  //ifstream pImgIn(imgName.c_str(), ios::in | ios::binary);
  //assert(pImgIn.good());

  int CHAR_BIT = 8;
  unsigned int mask = (1 << pixBitDepth) - 1;
  *bytesPerPix = (((pixBitDepth % CHAR_BIT) == 0) ? (pixBitDepth/CHAR_BIT) : (pixBitDepth/CHAR_BIT+1));

  FILE* pImgIn = fopen(imgName, "rb");

  if(pImgIn==NULL){
    printf("Error opening image %s\n", imgName);
    exit(1);
                  }

  void* img;

  int flip = 0;

  printf("readRawImg %d\n", *bytesPerPix);

  if (*bytesPerPix <= 1)
  {
    img =  malloc(width*height);
    unsigned char* iimg = img;
    unsigned char* tmpBuff = malloc(width*height);//new unsigned char[height*width];
    fread(tmpBuff,1,header,pImgIn); // throw away header
    //pImgIn.read((char *) tmpBuff, height*width);
    fread(tmpBuff,1,width*height,pImgIn);

  for( int y = 0; y<height; y++){
    for( int x  = 0; x<width; x++){
      int k = y*width+x;
      if(flip){k = (height-y-1)*width+x;}
      iimg[y*width+x] = (((unsigned int) tmpBuff[k]) & mask);
    }
                                }
    free(tmpBuff);
  }
  else if (*bytesPerPix <= 2)
    {
      img =  malloc(width*height*2);
      unsigned short *iimg = img;

      //unsigned char* tmpBuff = new unsigned char[2*height*width];
      unsigned char* tmpBuff = malloc(width*height*2);
      fread(tmpBuff,1,header,pImgIn); // throw away header
      //pImgIn.read((char *) tmpBuff, 2*height*width);
      fread(tmpBuff,1,width*height*2,pImgIn);

  for( int y = 0; y<height; y++){
    for( int x  = 0; x<width; x++){

      int k = y*width+x;
      if(flip){k = (height-y-1)*width+x;}
      if(flipEndian==1){
//        printf("FE %d\n",header);
        iimg[y*width+x] = (((unsigned int) tmpBuff[2*k+1] + (unsigned int) (tmpBuff[2*k] << 8)) & mask);
                    }else{
      iimg[y*width+x] = (((unsigned int) tmpBuff[2*k] + (unsigned int) (tmpBuff[2*k+1] << 8)) & mask);
                    }
                                  }
                                }

    free(tmpBuff);
    }
    else if (*bytesPerPix <= 4)
      {
        img =  malloc(width*height*4);
        unsigned int *iimg = img;
        //unsigned char* tmpBuff = new unsigned char[4*height*width];
        unsigned char* tmpBuff = malloc(width*height*4);
        fread(tmpBuff,1,header,pImgIn); // throw away header
        //pImgIn.read((char *) tmpBuff, 4*height*width);
        fread(tmpBuff,1,width*height*4,pImgIn);

  for( int y = 0; y<height; y++){
    for( int x  = 0; x<width; x++){
      int k = y*width+x;
      if(flip){k = (height-y-1)*width+x;}
      if(flipEndian==1){
        iimg[y*width+x] = (((unsigned int) tmpBuff[4*k+3] + (unsigned int) (tmpBuff[4*k+2] << 8) + (int) (tmpBuff[4*k+1] << 16) + (int) (tmpBuff[4*k] << 24)) & mask);
                    }else{
        iimg[y*width+x] = (((unsigned int) tmpBuff[4*k] + (unsigned int) (tmpBuff[4*k+1] << 8) + (int) (tmpBuff[4*k+2] << 16) + (int) (tmpBuff[4*k+3] << 24)) & mask);
                         }
      }
    }
    //delete[] tmpBuff;
    free(tmpBuff);
  }else{
    printf("in readImg - a max of 4 bytes/pixel is supported - please check input image/parameters)");
    exit(-1);
  }

  //printf("done\n");
  return (unsigned char*)img;
}

]]

orion.util={}

terra orion.util.endian(x : uint32) return x; end

terra orion.util.saveImageUC(
  filename : &int8, 
  width : int, 
  height : int,
  stride : int,
  channels : int,
  data : &uint8)

  return chack.saveImageUC( filename, width, height, stride, channels, data )
end

terra orion.util.saveImageF(
  filename : &int8, 
  width : int, 
  height : int, 
  stride : int,
  channels : int,
  data : &float)

  cstdio.printf("call saveImageF\n")
  return chack.saveImageF( filename, width, height, stride, channels, data )
end

terra orion.util.saveImageI(
  filename : &int8, 
  width : int, 
  height : int, 
  stride : int,
  channels : int,
  data : &int)

  cstdio.printf("call saveImageI\n")
  return chack.saveImageI( filename, width, height, stride, channels, data )
end

terra orion.util.saveImageAutoLevels(
  filename : &int8, 
  width : int, 
  height : int, 
  stride : int,
  channels : int,
  data : &float)

  return chack.saveImageAutoLevels( filename, width, height, stride, channels, data )
end


terra orion.util.loadBMP_UC(filename : &int8, width : &int, height : &int, channels : &int) : &uint8

  var currentCurPos : uint = 0

  var file  = cstdio.fopen(filename,"rb");

  if file==nil then
    cstdio.printf("File not found: %s",filename);
    return nil;
  end

  cstdio.fseek(file, 0, chack.seek_end());
  var totalfilesize = cstdio.ftell(file);

  cstdio.fseek(file, 2, chack.seek_set());
  currentCurPos = currentCurPos+2;

  var totalsize : uint32=0;	--headersize:56+ width*height*bpp
  var i : int = 0;

  i = cstdio.fread(&totalsize, sizeof(uint32), 1, file);
  if (i ~= 1)  then
    cstdio.printf("Error reading compression");
    return nil;
  end
  currentCurPos = currentCurPos+sizeof(uint32);

  totalsize=orion.util.endian(totalsize);

  -- seek through the bmp header, up to the width/height:
  cstdio.fseek(file, 4, chack.seek_cur());
  currentCurPos = currentCurPos+4;
  var headersize : uint32 =0;	--headersize:56+ width*height*bpp
  
  i = cstdio.fread(&headersize, sizeof(uint32), 1, file)
  if (i ~= 1) then
    cstdio.printf("Error reading compression");
    return nil;
  end
  currentCurPos = currentCurPos+sizeof(uint32);
  headersize=orion.util.endian(headersize);
  
  cstdio.fseek(file, 4, chack.seek_cur());
  currentCurPos = currentCurPos+4;

  i = cstdio.fread(width, 4, 1, file)
  if (i ~= 1) then
    cstdio.printf("Error reading file\n");
    return nil;
  end

  currentCurPos = currentCurPos+4;
  @width = orion.util.endian(@width);
  
  -- read the width
  if (i ~= 1) then
    cstdio.printf("Error reading width");
    return nil;
  end

  -- read the height 
  i = cstdio.fread(height, 4, 1, file)
  if (i ~= 1) then
    cstdio.printf("Error reading file\n");
    return nil;
  end

  currentCurPos = currentCurPos+4;
  @height = orion.util.endian(@height);
    
  if (i ~= 1) then
    cstdio.printf("Error reading height");
    return nil;
  end
    
  -- read the planes
  var planes : uint16;          -- number of planes in image (must be 1) 
  i=cstdio.fread(&planes, 2, 1, file)
  if (i ~= 1) then
    cstdio.printf("Error reading file\n");
    return nil;
  end

  currentCurPos = currentCurPos+2;
  planes=orion.util.endian(planes);
  
  if (i ~= 1) then
    cstdio.printf("Error reading planes");
    return nil;
  end
    
  if (planes ~= 1) then
    cstdio.printf("Planes is %d, not 1 like it should be",planes);
    return nil;
  end

  -- read the bpp
  var bpp: uint16;             -- number of bits per pixel (must be 24)
  i = cstdio.fread(&bpp, 2, 1, file)
  if (i ~= 1) then
    cstdio.printf("error reading bpp");
    return nil;
  end
  currentCurPos = currentCurPos+2;
  bpp=orion.util.endian(bpp);

  -- read compression
  var compression : uint32 =0;

  i = cstdio.fread(&compression, sizeof(uint32), 1, file)
  if (i ~= 1) then
    cstdio.printf("error reading compression");
    return nil;
  end
  currentCurPos = currentCurPos+sizeof(uint32);
  compression=orion.util.endian(compression);
  
  -- read csize
  var csize : uint32=0;

  i = cstdio.fread(&csize, sizeof(uint32), 1, file)
  if (i ~= 1) then
    cstdio.printf("error reading csize");
    return nil;
  end
  currentCurPos = currentCurPos+sizeof(uint32);
  csize=orion.util.endian(csize);
    
  if (bpp == 24) then
    @channels = 3;
  elseif (bpp ==32) then
    @channels = 4;
    -- greyscale images:
  elseif (bpp == 8) then
    @channels = 1;
  else
    cstdio.printf("Bpp from %s is not 8, 24, or 32: %u\n", filename, bpp);
    return nil;
  end
  
  var size : uint64 = (@width) * (@height) * (@channels);
  
  -- seek past the rest of the bitmap header.
  cstdio.fseek(file, 16, chack.seek_cur());
  currentCurPos = currentCurPos+16;

  -- bmps pad each row to be a multiple of 4 bytes
  var padding : int = 4 - ((@width) * (@channels) % 4);
  if padding==4 then padding=0 end

  -- allocate array for data
  --unsigned char *data=new unsigned char[size];
  var data = [&uint8](cstdlib.malloc(size*sizeof(uint8)))

  if (data == nil) then
    cstdio.printf("Error allocating memory for color-corrected image data");
    return nil;	
  end

  if(padding~=0)then
    
    --unsigned char *tempData=new unsigned char[size+padding*(*height)];
    var tempData  = [&uint8](cstdlib.malloc((size+padding*(@height))*sizeof(uint8)))
    
    cstdio.fseek(file, headersize-currentCurPos, chack.seek_cur());
    
    i = cstdio.fread(tempData, size+padding*(@height), 1, file)
    if (i ~= 1) then
      cstdio.printf("Error reading image data %d %d %d %d\n",padding, @width,@height,headersize);
      --delete[] tempData;
      cstdlib.free(tempData)
      return nil;
    end
    
    --for(int h=0; h<(@height); h++) do
    for h = 0,(@height) do
      cstring.memcpy(
	&(data[h*(@width)*(@channels)]),
	&tempData[h*(@width)*(@channels)+h*padding],
	(@width)*(@channels));
    end

    --delete[] tempData;
    cstdlib.free(tempData)
  else
    cstdio.fseek(file, headersize-currentCurPos, chack.seek_cur());
    
    i = cstdio.fread(data, size, 1, file)
    if (i ~= 1) then
      cstdio.printf("Error reading image data %d %d %ld %d %d %d %ld %d\n",headersize,currentCurPos,size,@width,@height, @channels,totalfilesize,totalsize);
      return nil;
    end
  end
  
  var temp :uint8= 0;

  if (@channels > 2) then
    --for (unsigned int j=0; j<size; j+=*channels ) do -- reverse all of the colors. (bgr -> rgb)
    for j=0,size,(@channels) do
      temp = data[j];
      data[j] = data[j+2];
      data[j+2] = temp;
    
      data[j]=data[j];
      data[j+1]=data[j+1];
      data[j+2]=data[j+2];
    end
  end
  
  cstdio.fclose(file);

  return data;
end

terra orion.util.saveImageJJM(filename : &int8, width : int, height : int, stride : int, channels: int, bits:int, floating:bool, isSigned:bool,data :&opaque) : bool
  var ext : &int8 = filename + (cstring.strlen(filename) - 3)
  if cstring.strcmp(ext,"jjm")==0 then
    cstdio.printf("WRITE JJM %s\n",filename)

    if width~=stride then
      cstdio.printf("UNSUPPORTED STRIDE\n")
      cstdlib.exit(1);
    end

    var file = cstdio.fopen(filename, "wb")

    if file==nil then
      cstdio.printf("Error opening file %s for write, probably directory doesn't exist\n",filename)
      return false
    end

    cstdio.fprintf(file,"jjm20\n")
    cstdio.fprintf(file,"%d %d %d\n",height,width,channels)
    if floating then
      cstdio.fprintf(file,"float_%d_0\n",bits)
    elseif isSigned then
      cstdio.fprintf(file,"fix_%d_0\n",bits)
    else
      cstdio.fprintf(file,"ufix_%d_0\n",bits)
    end

    cstdio.fwrite(data,channels*(bits/8),width*height,file)
    cstdio.fclose(file)
    return true
  end

  cstdio.printf("Error, can't save image as JJM with incorrect extension '%s' %s\n",filename,ext)
  return false
end

terra orion.util.loadImageJJM(filename : &int8, width : &int, height : &int, channels: &int, bits:&int) : &opaque
  var ext : &int8 = filename + (cstring.strlen(filename) - 3)
  if cstring.strcmp(ext,"jjm")==0 then
    var file = cstdio.fopen(filename, "rb")
    cstdio.fscanf(file,"jjm20\n")
    cstdio.fscanf(file,"%d %d %d\n",height,width,channels)
    cstdio.fscanf(file,"ufix_%d_0\n",bits)
    var data : &opaque = cstdlib.malloc(@channels*(@bits/8)*@width*@height)
    cstdio.fread(data,@channels*(@bits/8),@width*@height,file)
    cstdio.fclose(file)
    return data
  end

  cstdio.printf("Error, can't load image as JJM with incorrect extension '%s' %s\n",filename,ext)
  return nil
end

terra orion.util.loadImageUC(filename : &int8, width : &int, height : &int, channels :&int, bits : &int)
  var ext : &int8 = filename + (cstring.strlen(filename) - 3)

  if cstring.strcmp(ext,"bmp")==0 then
    @bits = 8
    return orion.util.loadBMP_UC(filename,width,height,channels);
  elseif (cstring.strcmp(ext,"ppm")==0) or cstring.strcmp(ext,"pgm")==0 then
    @bits = 8
    return chack.loadPPM_UC(filename,width,height,channels,bits);
  --elseif(cstring.strcmp(ext,"jjm")==0) then
  --  return chack.loadJJM_UC(filename,width,height,channels,bits);
  elseif(cstring.strcmp(ext,"jjm")==0) then
    return [&uint8](orion.util.loadImageJJM(filename,width,height,channels,bits))
  end

  cstdio.printf("unknown filetype %s\n",filename);
  return nil;
end

terra orion.util.loadRaw(filename : &int8, width : int, height : int, bits : int, header:int, flipEndian: bool, bytesOut: &int)
  return chack.readRawImg(filename,width,height,bits,header,uint8(flipEndian),bytesOut)
end

terra orion.util.saveRaw(
  filename : &int8, 
  width : int, 
  height : int, 
  stride : int,
  bits : int,
  data : &int)

  return chack.writeRawImgToFile(filename,width,height,stride,bits,data)
end

struct Image { 
  width : int, 
  height : int, 
  stride : int, 
  channels: int, -- this is always stored AoS
  bits : int, 
  floating : bool, -- is this floating point?
  isSigned : bool, -- is this signed?
  SOA : bool, -- is this stored as SOA?
  data : &opaque,
  -- it's possible that data doesn't point to the start of the array (strided images)
  -- dataPtr points to the start of the array
  dataPtr : &opaque
}

terra Image:init( 
  width : int, 
  height : int, 
  stride : int,
  channels : int, 
  bits : int, 
  floating : bool,
  isSigned : bool,
  SOA : bool,
  data : &opaque,
  dataPtr : &opaque)

  orionAssert(stride>=width, "stride < width")
  orionAssert(data>=dataPtr, "data < dataPtr")

  self.width = width
  self.height = height
  self.stride = stride
  self.channels = channels
  self.bits = bits
  self.floating = floating
  self.isSigned = isSigned
  self.SOA = SOA
  self.data = data
  self.dataPtr = dataPtr
end

terra Image:initSimple(
  width : int, 
  height : int, 
  channels : int, 
  bits : int, 
  floating : bool,
  isSigned : bool,
  SOA : bool,
  data : &opaque)

  self:init(width, height, width, channels, bits, floating, isSigned, SOA, data, data)
end

terra Image:initWithFile(filename : &int8)

  var width : int
  var height : int
  var channels : int
  var bits : int

  var data : &opaque = orion.util.loadImageUC(filename,&width,&height,&channels,&bits)

  self:init(width,height,width,channels,bits,false,false,false,data,data)
end

terra Image:initWithRaw(filename : &int8, w:int, h:int, bits:int)
  -- loadRaw always returns an int32
  var outBytes : int
  var data : &opaque = orion.util.loadRaw(filename,w,h,bits,0,false,&outBytes)

  self:init(w,h,w,1,outBytes*8,false,false,false,data,data)
end

-- header: number of header bits to ignore
-- flipEndian: if multibyte, flip the endian ordering
terra Image:initWithRaw(filename : &int8, w:int, h:int, bits:int, header : int, flipEndian : bool)
  -- loadRaw always returns an int32
  var bytesOut : int
  var data : &opaque = orion.util.loadRaw(filename,w,h,bits, header, flipEndian,&bytesOut)

  self:init(w,h,w,1,bytesOut*8,false,false,false,data,data)
end

terra Image:free()
  cstdlib.free(self.dataPtr)
end

-- this will take the image, do a deep copy, and in the process rearrange 
-- the image to remove the stride
terra Image:deepcopyUnstride()
  orionAssert(self.bits % 8 == 0, "bits must be mod 8")

  var bytes = (self.bits/8)
  var size = self.width*self.height*self.channels*bytes
  --var temp = cstdlib.malloc(size)
  var temp : &uint8
  cstdlib.posix_memalign( [&&opaque](&temp), pageSize, size)

  var channels = self.channels

  for y=0,self.height do
    for x = 0,self.width do
      for c = 0,channels do
        for b=0,bytes do
          temp[channels*bytes*(y*self.width+x)+c*bytes+b] = [&uint8](self.data)[channels*bytes*(y*self.stride+x)+c*bytes+b]
        end
      end
    end
  end
  
  var out : Image
  out.width = self.width
  out.height = self.height
  out.stride = self.width
  out.channels = self.channels
  out.bits = self.bits
  out.floating = self.floating
  out.isSigned = self.isSigned
  out.data = temp
  out.dataPtr = temp

  return out
end

terra Image:save(filename : &int8)
  var ext = filename + cstring.strlen(filename) - 3
  cstdio.printf("EXT %s\n",ext)

  if self.bits==8 and (self.channels==1 or self.channels==3) and self.floating==false and self.isSigned==false then
    if orion.verbose then cstdio.printf("Assuming uint8\n") end
    if cstring.strcmp(ext,"jjm")==0 then
       var us = self:deepcopyUnstride()
       orion.util.saveImageJJM( filename, self.width, self.height, self.width, self.channels, self.bits, self.floating, self.isSigned, us.data ) -- self.data )
       us:free()
    else 
       orion.util.saveImageUC(
	  filename,
	  self.width,
	  self.height,
	  self.stride,
	  self.channels,
	  [&uint8](self.data))
    end 
    return true
  elseif self.bits==32 and self.channels==1 and self.floating then
    if orion.verbose then cstdio.printf("saving a 32 bit 1 channel float\n") end
    orion.util.saveImageAutoLevels( filename, self.width, self.height, self.stride, 1, [&float](self.data) )
    return true
  elseif self.bits==32 and self.channels==1 and self.floating==false and cstring.strcmp(ext,"jjm")>0 then
    if orion.verbose then cstdio.printf("saving a 32 bit 1 channel float\n") end
    orion.util.saveImageI( filename, self.width, self.height, self.stride, 1, [&int](self.data) )
    return true
  elseif self.bits==32 and (self.channels==2 or self.channels==3) and self.floating then
    --cstdio.printf("Assuming that a 32 bit 3 channel image is float!!!!!!!!!\n")
    orion.util.saveImageF( filename, self.width, self.height, self.stride, self.channels, [&float](self.data) )
    return true
  end

  if self.floating then
    cstdio.printf("Error saving, unimplemented float type bits:%d channels:%d\n",self.bits,self.channels)
  elseif cstring.strcmp(ext,"jjm")==0 then
--    cstdio.printf("Error saving, unimplemented int type bits:%d channels:%d\n",self.bits,self.channels)
    var us =self:deepcopyUnstride()
     orion.util.saveImageJJM( filename, self.width, self.height, self.width, self.channels, self.bits, self.floating, self.isSigned, us.data ) -- self.data )
     us:free()
  else
    cstdio.printf("Error saving, unimplemented type float:%d signed:%d bits:%d channels:%d\n",self.floating,self.isSigned,self.bits,self.channels)
  end


  return false
end

terra Image:saveRaw(filename : &int8, bits:int)
  orionAssert(bits <= 32, "saveRaw only works on bits <= 32")
  orionAssert(self.bits == 32, "saveRaw only works on 32 bit images")
  orionAssert(self.floating == false, "saveRaw only works on int")

  orion.util.saveRaw(
    filename, 
    self.width, 
    self.height, 
    self.stride, 
    bits,
    -- unsafe cast, but we asserted this is 32 bit int
    [&int](self.data) )
end

-- flips the image in place
terra Image:flip()
  orionAssert(self.bits % 8 == 0, "bits must be mod 8 to flip")
  var bytes = (self.bits/8)*self.channels

  for y = 0,self.height/2 do
    var flipY = self.height-y-1
    for x = 0,self.stride do
      for b = 0,bytes do
        var tmp = [&uint8](self.data)[y*self.stride*bytes+x*bytes+b]
        [&uint8](self.data)[y*self.stride*bytes+x*bytes+b] = [&uint8](self.data)[flipY*self.stride*bytes+x*bytes+b]
        [&uint8](self.data)[flipY*self.stride*bytes+x*bytes+b] = tmp
      end
    end
  end
end

terra Image:downsample()
  orionAssert(self.bits % 8 == 0, "bits must be mod 8 to downsample")

  var widthd2 = (self.width/2)
  var heightd2 = (self.height/2)

  var chan = self.channels

--  orionAssert(chan==1,"lolol")

  for y= 0, heightd2 do
    for x= 0, widthd2 do

      if self.bits==8 and self.floating==false and self.isSigned==false then
        for c = 0, self.channels do
          var aa = [&uint8](self.data)[y*2*self.stride*chan+x*2*chan+c]
          var bb = [&uint8](self.data)[y*2*self.stride*chan+(x*2+1)*chan+c]
          var cc = [&uint8](self.data)[(y*2+1)*self.stride*chan+x*2*chan+c]
          var dd = [&uint8](self.data)[(y*2+1)*self.stride*chan+(x*2+1)*chan+c]
          
          var comb = float(aa)+float(bb)+float(cc)+float(dd)
          comb = comb/4
          [&uint8](self.data)[y*widthd2*chan+x*chan+c] = comb
        end
        
      else
        cstdio.printf("%d %d %d\n",self.bits,self.floating,self.isSigned)
        orionAssert(false,"unsupported Downsample")
      end

    end
  end

  self.width = widthd2
  self.height = heightd2
  self.stride = widthd2
end

-- can't do this in place for obvious reasons
terra Image:upsample()
  orionAssert(self.bits % 8 == 0, "bits must be mod 8 to upsample")
  orionAssert(self.bits == 32, "bits must be 32 to upsample")
  orionAssert(self.floating, "must be floating to upsample")
  orionAssert(self.isSigned==false, "must be floating to upsample (IS)")

  cstdio.printf("START US\n")
  var width2 = self.width*2
  var height2 = self.height*2

  var chan = self.channels

  var bpc = self.bits / 8
  var size = width2*height2*self.channels*bpc
  var temp : &uint8
  cstdlib.posix_memalign( [&&opaque](&temp), pageSize, size)

  var inF = [&float](self.data)
  var outF = [&float](temp)

  for y = 0, height2 do
    for x = 0, width2 do

        var lx = x/2
        var ly = y/2

        for c = 0, self.channels do

          var xp1 = 1
          var yp1 = 1

          if lx==self.width-1 then xp1=0 end
          if ly==self.height-1 then yp1=0 end

          var aa = inF[ly*self.stride*chan+lx*chan+c]
          var bb = inF[ly*self.stride*chan+(lx+xp1)*chan+c]
          var cc = inF[(ly+yp1)*self.stride*chan+lx*chan+c]
          var dd = inF[(ly+yp1)*self.stride*chan+(lx+xp1)*chan+c]

          var ix = float(x%2)/2
          var iy = float(y%2)/2

          var m1 = (aa*(1-ix)+bb*ix)
          var m2 = (cc*(1-ix)+dd*ix)

          outF[y*width2*chan+x*chan+c] = (m1*(1-iy)+m2*iy)
        end
    end
  end

  self:free()
  self.width = width2
  self.stride = width2
  self.height = height2
  self.data = temp
  self.dataPtr = temp
end


local function makeConvert(fromType, toType, toTypeBits, toTypeFloating)
  assert(type(toTypeBits)=="number")
  assert(type(toTypeFloating)=="boolean")

  return terra(self:&Image)
    orionAssert(sizeof(fromType)*8==self.bits, "unsupported int32 conversion")
    orionAssert(self.stride==self.width, "toInt32 stride not supported")

    var size = self.width*self.height*self.channels*sizeof(toType)
    var temp : &toType
    cstdlib.posix_memalign( [&&opaque](&temp), pageSize, size)

    var inF = [&fromType](self.data)

    var lineWidth = self.width*self.channels
    for y = 0, self.height do
      for x = 0, self.width do
        for c = 0, self.channels do
          var aa = inF[y*lineWidth + x*self.channels + c]
          temp[y*lineWidth + x*self.channels + c] = aa
        end
      end
    end
    
    self:free()
    self.bits = toTypeBits
    self.floating = toTypeFloating
    self.isSigned = false
    self.data = temp
    self.dataPtr = temp
  end
end

Image.methods.uint8ToFloat32 = makeConvert(uint8, float, 32, true)
Image.methods.int32ToFloat32 = makeConvert(int32, float, 32, true)

terra Image:toFloat32()
  orionAssert(self.floating==false, "you can't converting float to float")
  if self.bits==8 and self.isSigned==false then
    self:uint8ToFloat32()
  elseif self.bits==32 and self.isSigned then
    self:int32ToFloat32()
  else
    cstdio.printf("bits %d\n",self.bits)
    orionAssert(false, "unsupported float32 conversion")
  end
end

Image.methods.uint8ToUint32 = makeConvert(uint8,uint32, 32, false)
Image.methods.uint16ToUint32 = makeConvert(uint16,uint32, 32, false)

terra Image:toUint32()

  if self.bits==8 and self.isSigned==false and self.floating==false then
    self:uint8ToUint32()
  elseif self.bits==16 and self.isSigned==false and self.floating==false then
    self:uint16ToUint32()
  else
    cstdio.printf("bits %d\n",self.bits)
    orionAssert(false, "unsupported float32 conversion")
  end
end


Image.methods.float32ToUint8 = makeConvert(float,uint8,8, false)

terra Image:toUint8()

  if self.bits==32 and self.isSigned==false and self.floating==true then
    self:float32ToUint8()
  else
    cstdio.printf("bits %d\n",self.bits)
    orionAssert(false, "unsupported toUint8 conversion")
  end
end

-- convert a separate R,G,B image into a single RGB image
function makeToAOS(channels, ty)
  assert(type(channels)=="number")
  assert(terralib.types.istype(ty))

  local symbs = {}
--  local strideSymbs = {}
  -- first C symbols are the pointers to the inputs,
  -- second C symbols are the strides of the inputs
  -- C is the number of channels
  for i=1,channels do table.insert(symbs,symbol(&ty)) end
  for i=1,channels do table.insert(symbs,symbol(int)) end

  local res = symbol(&ty)
  local c = symbol(int)
  local strideSymb = symbol(int)

  local kernel = {}
  local nextLine = {}
  
  for i=1,channels do
    table.insert(kernel, quote if c==(i-1) then @[res] = @[symbs[i]]; [symbs[i]] = [symbs[i]]+1; end end)
    table.insert(nextLine, quote [symbs[i]] = [symbs[i]] - strideSymb + [symbs[channels+i]]; end)
  end

  return 
    terra([strideSymb], height:int, [symbs])
    if orion.verbose then cstdio.printf("TO AOS\n") end
    var [res] = [&ty](cstdlib.malloc(channels*strideSymb*height*sizeof(ty)))
    var ores = res

    for y=0,height do
      for x=0,strideSymb do
        for [c]=0,channels do
          kernel
          res = res + 1
        end
      end
      nextLine
    end


    return ores
    end
end

terra Image:toAOS()

end

-- convert from AoS to SoA
function makeToSOA(channels, ty)
  assert(type(channels)=="number")
  assert(channels>0)
  assert(terralib.types.istype(ty))

  local ptr = &ty
  return 
    terra(width:int,
          height:int,
          index:int,
      from : ptr,
      to : ptr)

      if orion.verbose then cstdio.printf("TO SOA\n") end
      orionAssert(index < channels, "index must be < channels")

      for y=0,height do
        for x=0,width do
          for c=0,channels do
            if c==index then @to=@from; to=to+1; end
            from = from + 1
          end
        end
      end
    end
end

terra Image:toSOA()

end